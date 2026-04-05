import AVFoundation
import Foundation
import Models
import os

/// Manages video playback for a single viewing session using AVPlayer.
///
/// Unlike `AudioPlaybackManager` (a singleton for music), this is created per video playback session
/// and is tied to the video player view lifecycle. The app layer resolves stream URLs and passes
/// a `StreamInfo` to `loadAndPlay`.
@Observable
@MainActor
public final class VideoPlaybackManager {
    // MARK: - Observable State

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isBuffering: Bool = false
    public private(set) var subtitleTracks: [SubtitleTrack] = []
    public var selectedSubtitleIndex: Int? = nil

    // PiP
    public private(set) var isPiPActive: Bool = false
    public private(set) var isPiPPossible: Bool = false

    // Next episode auto-play
    public private(set) var nextEpisode: MediaItem? = nil
    public private(set) var showNextEpisodeCountdown: Bool = false
    public private(set) var nextEpisodeCountdown: Int = 10

    // The item being played
    public private(set) var currentItem: MediaItem? = nil

    // MARK: - Player Access

    /// The underlying AVPlayer — exposed for the UI layer to create a video rendering view.
    public let player: AVPlayer = AVPlayer()

    // MARK: - Callbacks (set by the app layer)

    /// Called when playback starts. App layer uses this for server reporting.
    public var onPlaybackStart: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called periodically (~every 10s) during playback.
    public var onPlaybackProgress: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called when playback stops.
    public var onPlaybackStopped: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called when the user triggers "play next episode".
    public var onPlayNextEpisode: (@MainActor (MediaItem) -> Void)?

    // MARK: - Internal

    @ObservationIgnored private nonisolated(unsafe) var timeObserver: Any?
    @ObservationIgnored private nonisolated(unsafe) var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var bufferObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var rateObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var endOfVideoTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var progressReportTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var countdownTask: Task<Void, Never>?

    #if os(iOS)
        @ObservationIgnored private nonisolated(unsafe) var pipController:
            AVPictureInPictureController?
        @ObservationIgnored private nonisolated(unsafe) var pipDelegate: PiPDelegate?
    #endif

    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "VideoPlayback")

    // MARK: - Init / Deinit

    public init() {
        setupAudioSession()
        setupPlayer()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        rateObserver?.invalidate()
        endOfVideoTask?.cancel()
        progressReportTask?.cancel()
        countdownTask?.cancel()
    }

    // MARK: - Public API

    /// Load a video item and start playback.
    public func loadAndPlay(
        item: MediaItem, streamInfo: StreamInfo, startPosition: TimeInterval = 0
    ) {
        stop()

        currentItem = item

        // Parse subtitle tracks from stream info
        subtitleTracks = streamInfo.mediaStreams
            .filter { $0.type == .subtitle }
            .map { stream in
                SubtitleTrack(
                    id: stream.index,
                    title: stream.title ?? stream.language ?? "Track \(stream.index)",
                    language: stream.language,
                    isExternal: stream.isExternal,
                    url: nil  // App layer will provide subtitle URLs separately if needed
                )
            }

        let playerItem = AVPlayerItem(url: streamInfo.url)
        player.replaceCurrentItem(with: playerItem)

        // Observe the new item's status
        observePlayerItem(playerItem)

        // Seek to start position if resuming
        if startPosition > 0 {
            let cmTime = CMTime(seconds: startPosition, preferredTimescale: 600)
            player.seek(to: cmTime) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.player.play()
                    self?.isPlaying = true
                }
            }
        } else {
            player.play()
            isPlaying = true
        }

        // Start progress reporting
        startProgressReporting()

        // Report playback start
        Task { [weak self] in
            guard let self, let item = self.currentItem else { return }
            await self.onPlaybackStart?(item, startPosition)
        }

        logger.info("Loading video: \(item.title) (transcoded: \(streamInfo.isTranscoded))")
    }

    /// Set the next episode for auto-play (enables countdown near end).
    public func setNextEpisode(_ episode: MediaItem?) {
        nextEpisode = episode
    }

    /// Resume playback.
    public func play() {
        player.play()
        isPlaying = true
    }

    /// Pause playback.
    public func pause() {
        player.pause()
        isPlaying = false
    }

    /// Toggle between play and pause.
    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Seek to a specific position in the video.
    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                self?.currentTime = time
                // Reset countdown if user seeks back
                self?.showNextEpisodeCountdown = false
                self?.countdownTask?.cancel()
            }
        }
    }

    /// Skip forward by the given number of seconds (default 10).
    public func skipForward(_ seconds: TimeInterval = 10) {
        seek(to: min(currentTime + seconds, duration))
    }

    /// Skip backward by the given number of seconds (default 10).
    public func skipBackward(_ seconds: TimeInterval = 10) {
        seek(to: max(currentTime - seconds, 0))
    }

    #if os(iOS)
        /// Toggle Picture-in-Picture mode.
        public func togglePiP() {
            guard let pip = pipController else { return }
            if pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            } else {
                pip.startPictureInPicture()
            }
        }

        /// Call this from the UI layer once an AVPlayerLayer is available.
        public func setupPiP(playerLayer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            let pip = AVPictureInPictureController(playerLayer: playerLayer)
            let delegate = PiPDelegate { [weak self] active in
                Task { @MainActor [weak self] in
                    self?.isPiPActive = active
                }
            }
            pip?.delegate = delegate
            self.pipController = pip
            self.pipDelegate = delegate
            self.isPiPPossible = pip != nil
        }
    #endif

    /// Stop playback entirely and reset all state.
    public func stop() {
        let position = currentTime
        let item = currentItem

        player.pause()
        player.replaceCurrentItem(with: nil)

        isPlaying = false
        currentTime = 0
        duration = 0
        isBuffering = false
        currentItem = nil
        subtitleTracks = []
        selectedSubtitleIndex = nil
        showNextEpisodeCountdown = false
        nextEpisode = nil

        progressReportTask?.cancel()
        countdownTask?.cancel()

        // Report playback stopped
        if let item {
            Task { [weak self] in
                await self?.onPlaybackStopped?(item, position)
            }
        }

        logger.info("Stopped video playback")
    }

    /// Trigger playing the next episode (called by UI countdown or button).
    public func playNextEpisode() {
        guard let next = nextEpisode else { return }
        showNextEpisodeCountdown = false
        countdownTask?.cancel()
        onPlayNextEpisode?(next)
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                logger.error("Failed to configure audio session: \(error.localizedDescription)")
            }
        #endif
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        player.allowsExternalPlayback = true  // AirPlay

        // Periodic time observer — updates currentTime and duration every 0.5s
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds

                if let dur = self.player.currentItem?.duration, dur.isNumeric, !dur.isIndefinite {
                    self.duration = dur.seconds
                }

                // Check for next episode countdown trigger (30s from end)
                self.checkNextEpisodeCountdown()
            }
        }

        // Observe rate changes for external play/pause (e.g. stalling, AirPlay)
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let rate = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let playing = rate > 0
                if self.isPlaying != playing {
                    self.isPlaying = playing
                }
            }
        }

        // Observe end of video via async notification stream
        endOfVideoTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime)
            {
                guard let self else { break }
                self.handleVideoEnded()
            }
        }
    }

    // MARK: - Player Item Observation

    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    if item.duration.isNumeric, !item.duration.isIndefinite {
                        self.duration = item.duration.seconds
                    }
                    self.isBuffering = false
                case .failed:
                    self.logger.error(
                        "Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                    self.isBuffering = false
                default:
                    break
                }
            }
        }

        bufferObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) {
            [weak self] _, change in
            guard let isEmpty = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.isBuffering = isEmpty
            }
        }
    }

    // MARK: - Progress Reporting

    private func startProgressReporting() {
        progressReportTask?.cancel()
        progressReportTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                guard let self, let item = self.currentItem, self.isPlaying else { continue }
                await self.onPlaybackProgress?(item, self.currentTime)
            }
        }
    }

    // MARK: - Next Episode Countdown

    private func checkNextEpisodeCountdown() {
        guard nextEpisode != nil,
            !showNextEpisodeCountdown,
            duration > 0,
            duration - currentTime <= 30,
            duration - currentTime > 0,
            isPlaying
        else { return }

        showNextEpisodeCountdown = true
        nextEpisodeCountdown = min(10, Int(duration - currentTime))
        startCountdown()
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                if self.nextEpisodeCountdown > 1 {
                    self.nextEpisodeCountdown -= 1
                } else {
                    self.playNextEpisode()
                    break
                }
            }
        }
    }

    // MARK: - Video End

    private func handleVideoEnded() {
        logger.info("Video ended")
        isPlaying = false

        if let item = currentItem {
            Task { [weak self] in
                await self?.onPlaybackStopped?(item, self?.duration ?? 0)
            }
        }

        if nextEpisode != nil {
            playNextEpisode()
        }
    }
}

#if os(iOS)
    // MARK: - PiP Delegate

    /// Delegate for AVPictureInPictureController that bridges to a closure.
    private final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate,
        @unchecked Sendable
    {
        private let onActiveChanged: @Sendable (Bool) -> Void

        init(onActiveChanged: @escaping @Sendable (Bool) -> Void) {
            self.onActiveChanged = onActiveChanged
        }

        func pictureInPictureControllerDidStartPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            onActiveChanged(true)
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            onActiveChanged(false)
        }
    }
#endif
