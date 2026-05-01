import AVFoundation
import AVKit
import Foundation
import MediaPlayer
import Models
import os

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

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
    public private(set) var selectedSubtitleIndex: Int? = nil

    /// The current subtitle text to display as an overlay (for external/sideloaded subtitles).
    public private(set) var currentSubtitleText: String? = nil

    // Audio tracks
    public private(set) var audioTracks: [AudioTrack] = []
    public var selectedAudioTrackIndex: Int? = nil {
        didSet { applyAudioTrackSelection() }
    }

    // Playback speed
    public private(set) var playbackSpeed: Float = 1.0

    // Aspect ratio / video gravity
    public private(set) var videoGravity: AVLayerVideoGravity = .resizeAspect

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

    /// Called to get the artwork URL for NowPlaying info. Set by the app layer.
    public var artworkURLProvider: (@MainActor (MediaItem) -> URL?)?

    // MARK: - Callbacks (set by the app layer)

    /// Called when playback starts. App layer uses this for server reporting.
    public var onPlaybackStart: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called periodically (~every 10s) during playback.
    public var onPlaybackProgress: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called when playback stops.
    public var onPlaybackStopped: (@MainActor (MediaItem, TimeInterval) async -> Void)?
    /// Called when the user triggers "play next episode".
    public var onPlayNextEpisode: (@MainActor (MediaItem) -> Void)?
    /// Called when playback fails (e.g. AVPlayerItem enters .failed status).
    public var onPlaybackError: (@MainActor (MediaItem, Error) -> Void)?

    // MARK: - Internal

    @ObservationIgnored private nonisolated(unsafe) var timeObserver: Any?
    /// The item ID for which we're currently loading artwork (to discard stale loads).
    @ObservationIgnored private var nowPlayingArtworkItemId: ItemID?

    @ObservationIgnored private nonisolated(unsafe) var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var bufferObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var rateObserver: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var endOfVideoTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var progressReportTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var countdownTask: Task<Void, Never>?

    /// AVMediaSelectionGroup for subtitle tracks (populated on .readyToPlay).
    @ObservationIgnored private nonisolated(unsafe) var legibleSelectionGroup:
        AVMediaSelectionGroup?
    /// AVMediaSelectionGroup for audio tracks (populated on .readyToPlay).
    @ObservationIgnored private nonisolated(unsafe) var audibleSelectionGroup:
        AVMediaSelectionGroup?

    /// Parsed external subtitle cues (populated by `loadExternalSubtitle`).
    @ObservationIgnored private var externalSubtitleCues: [SubtitleCue] = []
    /// Task that fetches and parses an external subtitle file.
    @ObservationIgnored private var externalSubtitleTask: Task<Void, Never>?

    #if os(iOS)
        @ObservationIgnored private nonisolated(unsafe) var pipController:
            AVPictureInPictureController?
        @ObservationIgnored private nonisolated(unsafe) var pipDelegate: PiPDelegate?
    #endif

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "VideoPlayback")

    /// The available playback speed options.
    public static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// The available video gravity options for aspect ratio cycling.
    private static let gravityOptions: [AVLayerVideoGravity] = [
        .resizeAspect, .resizeAspectFill,
    ]

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

        // Parse subtitle tracks from stream info as initial metadata.
        // These will be replaced by AVPlayer-discovered tracks when the asset loads.
        subtitleTracks = streamInfo.mediaStreams
            .filter { $0.type == .subtitle }
            .map { stream in
                SubtitleTrack(
                    id: stream.index,
                    title: stream.title ?? stream.language ?? "Track \(stream.index)",
                    language: stream.language,
                    isExternal: stream.isExternal,
                    url: nil
                )
            }

        logger.info(
            "Loading stream: url=\(streamInfo.url.absoluteString) method=\(streamInfo.playMethod.rawValue) container=\(streamInfo.container ?? "unknown") video=\(streamInfo.videoCodec ?? "unknown") audio=\(streamInfo.audioCodec ?? "unknown")"
        )

        let playerItem = AVPlayerItem(url: streamInfo.url)
        player.replaceCurrentItem(with: playerItem)

        // Observe the new item's status
        observePlayerItem(playerItem)

        // Seek to start position if resuming
        if startPosition > 0 {
            let cmTime = CMTime(seconds: startPosition, preferredTimescale: 600)
            player.seek(to: cmTime) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.player.play()
                    if self.playbackSpeed != 1.0 {
                        self.player.rate = self.playbackSpeed
                    }
                    self.isPlaying = true
                }
            }
        } else {
            player.play()
            if playbackSpeed != 1.0 {
                player.rate = playbackSpeed
            }
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

        setupRemoteCommands()
        updateNowPlayingInfo()
    }

    /// Set the next episode for auto-play (enables countdown near end).
    public func setNextEpisode(_ episode: MediaItem?) {
        nextEpisode = episode
    }

    /// Resume playback.
    public func play() {
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
        isPlaying = true
        updateNowPlayingPlaybackState()
    }

    /// Pause playback.
    public func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingPlaybackState()
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
                self?.updateNowPlayingPlaybackState()
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

    // MARK: - Playback Speed

    /// Set the playback speed. Clamped to 0.5–2.0.
    public func setSpeed(_ speed: Float) {
        let clamped = max(0.5, min(speed, 2.0))
        playbackSpeed = clamped
        if isPlaying {
            player.rate = clamped
        }
        logger.info("Playback speed set to \(clamped)x")
    }

    /// Cycle to the next speed option.
    public func cycleSpeed() {
        let options = Self.speedOptions
        if let idx = options.firstIndex(of: playbackSpeed) {
            let nextIdx = (idx + 1) % options.count
            setSpeed(options[nextIdx])
        } else {
            // Find the closest option above current speed
            if let next = options.first(where: { $0 > playbackSpeed }) {
                setSpeed(next)
            } else {
                setSpeed(options[0])
            }
        }
    }

    // MARK: - Aspect Ratio

    /// Cycle between .resizeAspect (fit) and .resizeAspectFill (fill/zoom).
    public func cycleAspectRatio() {
        let options = Self.gravityOptions
        if let idx = options.firstIndex(of: videoGravity) {
            let nextIdx = (idx + 1) % options.count
            videoGravity = options[nextIdx]
        } else {
            videoGravity = .resizeAspect
        }
        logger.info("Video gravity changed to \(self.videoGravity.rawValue)")
    }

    // MARK: - Track Selection

    /// Select a subtitle track by index, or nil to disable subtitles.
    /// When AVPlayer doesn't expose a legible media-selection group (common for
    /// Jellyfin external-delivery subtitles), pass the WebVTT URL so the manager
    /// can fetch, parse, and overlay them.
    public func selectSubtitle(at index: Int?, externalURL: URL? = nil) {
        // Cancel any in-flight external subtitle fetch
        externalSubtitleTask?.cancel()
        externalSubtitleTask = nil
        externalSubtitleCues = []
        currentSubtitleText = nil

        selectedSubtitleIndex = index

        guard let index else {
            // Turning off subtitles — deselect native track if available
            if let group = legibleSelectionGroup, let playerItem = player.currentItem {
                playerItem.select(nil, in: group)
                logger.info("Subtitles disabled")
            }
            return
        }

        // Always use external subtitle loading — the server subtitle list
        // uses server stream indices which don't map 1:1 to AVPlayer's
        // legible group option indices, and the Jellyfin /Subtitles endpoint
        // reliably converts any format to VTT on the fly.
        if let url = externalURL {
            externalSubtitleTask = Task { [weak self] in
                await self?.loadExternalSubtitle(from: url)
            }
        } else {
            logger.warning("No legible group and no external URL for subtitle index \(index)")
        }
    }

    /// Append a new subtitle track to the available tracks list.
    ///
    /// Used when an external subtitle is downloaded (e.g. from OpenSubtitles)
    /// and needs to appear in the subtitle picker without re-resolving the stream.
    public func appendSubtitleTrack(_ track: SubtitleTrack) {
        subtitleTracks.append(track)
    }

    /// Select an audio track by index, or nil for default.
    public func selectAudioTrack(at index: Int?) {
        selectedAudioTrackIndex = index
    }

    // MARK: - PiP

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
        externalSubtitleTask?.cancel()
        externalSubtitleTask = nil
        externalSubtitleCues = []
        currentSubtitleText = nil
        audioTracks = []
        selectedAudioTrackIndex = nil
        showNextEpisodeCountdown = false
        nextEpisode = nil
        videoGravity = .resizeAspect
        legibleSelectionGroup = nil
        audibleSelectionGroup = nil

        progressReportTask?.cancel()
        countdownTask?.cancel()

        teardownRemoteCommands()

        // Report playback stopped
        if let item {
            Task { [weak self] in
                await self?.onPlaybackStopped?(item, position)
            }
        }

        logger.info("Stopped video playback")
    }

    /// Dismiss the next-episode countdown overlay without triggering playback.
    public func dismissNextEpisodeCountdown() {
        showNextEpisodeCountdown = false
        countdownTask?.cancel()
    }

    /// Trigger playing the next episode (called by UI countdown or button).
    public func playNextEpisode() {
        guard let next = nextEpisode else { return }
        nextEpisode = nil
        showNextEpisodeCountdown = false
        countdownTask?.cancel()

        // Reset progress immediately so the UI doesn't show stale values
        // from the old episode during the async transition to the next one
        currentTime = 0
        duration = 0

        onPlayNextEpisode?(next)
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        #if !os(macOS)
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

                // Update external subtitle overlay text
                self.updateExternalSubtitleText()

                // Update now playing playback position
                self.updateNowPlayingPlaybackState()

                // Check for next episode countdown trigger (30s from end)
                self.checkNextEpisodeCountdown()
            }
        }

        // Observe rate changes for external play/pause (e.g. stalling, AirPlay)
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let rate = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // When using custom playback speed, the rate might be > 1 while playing.
                // Treat rate > 0 as playing, rate == 0 as paused.
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

                    // Discover selectable audio and subtitle tracks from the loaded asset
                    self.discoverMediaSelectionTracks(item)

                case .failed:
                    let error =
                        item.error
                        ?? NSError(
                            domain: "VideoPlayback",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown playback error"]
                        )
                    let nsError = error as NSError
                    self.logger.error(
                        "Player item failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
                    )
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        self.logger.error(
                            "Underlying error: domain=\(underlyingError.domain) code=\(underlyingError.code) description=\(underlyingError.localizedDescription)"
                        )
                    }
                    if let failureReason = nsError.localizedFailureReason {
                        self.logger.error("Failure reason: \(failureReason)")
                    }
                    if let url = (item.asset as? AVURLAsset)?.url {
                        self.logger.error("Failed URL: \(url.absoluteString)")
                    }
                    self.isBuffering = false
                    if let currentItem = self.currentItem {
                        self.onPlaybackError?(currentItem, error)
                    }
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

    // MARK: - Media Selection Track Discovery

    /// Discovers selectable audio and subtitle tracks from the AVPlayerItem's asset.
    ///
    /// Called when the player item reaches `.readyToPlay`. This uses AVMediaSelectionGroup
    /// to enumerate the tracks that AVPlayer can actually switch between, as opposed to
    /// the metadata from StreamInfo which may not correspond to selectable options.
    private func discoverMediaSelectionTracks(_ playerItem: AVPlayerItem) {
        let asset = playerItem.asset

        Task { [weak self] in
            guard let self else { return }

            // Store the legible selection group for reference, but keep the
            // authoritative subtitle list from the server metadata.  AVPlayer
            // often discovers only a subset (e.g. HLS-embedded tracks) which
            // would hide external/sidecar subtitles the server knows about.
            if let legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible) {
                self.legibleSelectionGroup = legibleGroup
                self.logger.info(
                    "Discovered legible group with \(legibleGroup.options.count) option(s) from AVAsset (keeping server subtitle list)"
                )
            }

            // Discover audio tracks
            if let audibleGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                self.audibleSelectionGroup = audibleGroup

                let discovered = audibleGroup.options.enumerated().map { index, option in
                    AudioTrack(
                        id: index,
                        title: option.displayName,
                        language: option.locale?.language.languageCode?.identifier,
                        codec: nil,
                        channels: nil,
                        isDefault: option == audibleGroup.defaultOption
                    )
                }

                if !discovered.isEmpty {
                    self.audioTracks = discovered

                    // Set the currently selected audio track to the default
                    if let defaultIdx = discovered.firstIndex(where: { $0.isDefault }) {
                        self.selectedAudioTrackIndex = defaultIdx
                    }

                    self.logger.info("Discovered \(discovered.count) audio track(s) from AVAsset")
                }
            }
        }
    }

    // MARK: - Track Selection (internal)

    // MARK: - External Subtitle Loading

    /// Fetch a WebVTT/SRT subtitle file and parse it into cues for overlay rendering.
    private func loadExternalSubtitle(from url: URL) async {
        logger.info("Fetching external subtitle: \(url.absoluteString)")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            guard let content = String(data: data, encoding: .utf8) else {
                logger.error("External subtitle data is not valid UTF-8")
                return
            }
            let cues = WebVTTParser.parse(content)
            guard !Task.isCancelled else { return }
            externalSubtitleCues = cues
            logger.info("Loaded \(cues.count) external subtitle cue(s)")
            // Immediately update the displayed text for the current time
            updateExternalSubtitleText()
        } catch {
            if !Task.isCancelled {
                logger.error("Failed to load external subtitle: \(error.localizedDescription)")
            }
        }
    }

    /// Update `currentSubtitleText` based on the current playback time and loaded cues.
    private func updateExternalSubtitleText() {
        guard !externalSubtitleCues.isEmpty else {
            if currentSubtitleText != nil { currentSubtitleText = nil }
            return
        }
        let time = currentTime
        // Binary search for the cue whose time range contains the current playback time.
        // Cues are sorted by startTime, so we find the last cue whose startTime ≤ time.
        let newText = binarySearchCue(at: time)?.text
        if currentSubtitleText != newText {
            currentSubtitleText = newText
        }
    }

    /// Binary search for the active subtitle cue at the given time.
    ///
    /// Finds the last cue whose `startTime ≤ time`, then checks if `time < endTime`.
    /// Returns `nil` if no cue spans the given time. O(log n) complexity.
    private func binarySearchCue(at time: TimeInterval) -> SubtitleCue? {
        var low = 0
        var high = externalSubtitleCues.count - 1
        var result = -1

        // Find the rightmost cue with startTime <= time
        while low <= high {
            let mid = (low + high) / 2
            if externalSubtitleCues[mid].startTime <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard result >= 0 else { return nil }
        let cue = externalSubtitleCues[result]
        return time < cue.endTime ? cue : nil
    }

    /// Applies the current `selectedAudioTrackIndex` to the AVPlayer.
    private func applyAudioTrackSelection() {
        guard let playerItem = player.currentItem, let group = audibleSelectionGroup else { return }

        if let index = selectedAudioTrackIndex, index < group.options.count {
            let option = group.options[index]
            playerItem.select(option, in: group)
            logger.info("Selected audio track: \(option.displayName)")
        } else if let defaultOption = group.defaultOption {
            playerItem.select(defaultOption, in: group)
            logger.info("Reverted to default audio track")
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

    // MARK: - Now Playing Info

    /// Set up remote command center for video playback controls.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipForward()
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipBackward()
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = positionEvent.positionTime
            Task { @MainActor [weak self] in
                self?.seek(to: position)
            }
            return .success
        }

        // Next episode from lock screen
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playNextEpisode()
            }
            return .success
        }
    }

    /// Remove all remote command targets and clear now playing info.
    private func teardownRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Update now playing info with the current video metadata.
    private func updateNowPlayingInfo() {
        guard let item = currentItem else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0,
            MPMediaItemPropertyMediaType: MPMediaType.movie.rawValue,
        ]

        if let seriesName = item.seriesName {
            info[MPMediaItemPropertyArtist] = seriesName
        }

        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            info[MPMediaItemPropertyAlbumTitle] = "Season \(season), Episode \(episode)"
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Load artwork asynchronously
        if let url = artworkURLProvider?(item) {
            loadNowPlayingArtwork(from: url)
        }
    }

    /// Update only the playback position in NowPlaying (lightweight, called on timer).
    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackSpeed) : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Download artwork and set it in now playing info.
    private func loadNowPlayingArtwork(from url: URL) {
        let itemId = currentItem?.id
        nowPlayingArtworkItemId = itemId

        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard let self, self.nowPlayingArtworkItemId == itemId else { return }

            #if canImport(UIKit)
                guard let image = UIImage(data: data) else { return }
                let size = image.size
            #elseif canImport(AppKit)
                guard let image = NSImage(data: data) else { return }
                let size = image.size
            #endif

            let artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
            guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

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
