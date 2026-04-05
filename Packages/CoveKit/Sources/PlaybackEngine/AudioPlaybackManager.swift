import AVFoundation
import Foundation
import Models
import os

/// Manages audio playback using AVQueuePlayer with gapless transitions, queue management,
/// and lock screen integration via NowPlayingService.
@Observable
@MainActor
public final class AudioPlaybackManager {
    // MARK: - Observable State

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public let queue: PlayQueue = PlayQueue()

    /// Closure that resolves a Track to a streaming URL. Set by the app layer.
    public var streamURLResolver: (@Sendable (Track) -> URL?)?

    /// Closure that provides artwork URL for a track. Set by the app layer.
    public var artworkURLResolver: (@Sendable (Track) -> URL?)?

    // MARK: - Internal

    private let player: AVQueuePlayer = AVQueuePlayer()
    @ObservationIgnored private nonisolated(unsafe) var timeObserver: Any?
    @ObservationIgnored private nonisolated(unsafe) var itemObservers: [NSKeyValueObservation] = []
    private let nowPlayingService = NowPlayingService()
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "AudioPlayback")

    /// Maps AVPlayerItem instances to their corresponding Track for identification.
    @ObservationIgnored private var playerItemToTrack: [AVPlayerItem: Track] = [:]

    /// Task observing AVPlayerItemDidPlayToEndTime for automatic track advancement.
    @ObservationIgnored private nonisolated(unsafe) var endOfTrackTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    public init() {
        setupAudioSession()
        setupPlayer()
        nowPlayingService.setup()
        setupRemoteCommandHandlers()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        endOfTrackTask?.cancel()
        for observation in itemObservers {
            observation.invalidate()
        }
    }

    // MARK: - Public API

    /// Start playing a list of tracks from a specific index.
    public func play(tracks: [Track], startingAt index: Int = 0) {
        queue.load(tracks: tracks, startingAt: index)
        rebuildPlayerQueue()
        player.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        logger.info("Playing \(tracks.count) tracks, starting at index \(index)")
    }

    /// Resume playback.
    public func resume() {
        guard queue.currentTrack != nil else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
        logger.debug("Resumed playback")
    }

    /// Pause playback.
    public func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        logger.debug("Paused playback")
    }

    /// Toggle between play and pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Skip to the next track.
    public func next() {
        guard queue.forceAdvance() != nil else {
            logger.info("No next track available")
            stop()
            return
        }

        rebuildPlayerQueue()
        player.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        logger.info("Skipped to next track: \(self.queue.currentTrack?.title ?? "unknown")")
    }

    /// Go to the previous track, or restart the current track if more than 3 seconds in.
    public func previous() {
        if currentTime > 3 {
            seek(to: 0)
            logger.debug("Restarting current track (was \(self.currentTime)s in)")
            return
        }

        guard queue.forceGoBack() != nil else {
            logger.info("No previous track available")
            return
        }

        rebuildPlayerQueue()
        player.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        logger.info("Went to previous track: \(self.queue.currentTrack?.title ?? "unknown")")
    }

    /// Seek to a specific position in the current track.
    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time
                self.nowPlayingService.updatePlaybackState(
                    isPlaying: self.isPlaying,
                    currentTime: self.currentTime,
                    duration: self.duration
                )
            }
        }
    }

    /// Stop playback entirely and clear the queue.
    public func stop() {
        player.pause()
        player.removeAllItems()
        playerItemToTrack.removeAll()
        queue.clear()
        isPlaying = false
        currentTime = 0
        duration = 0
        nowPlayingService.teardown()
        logger.info("Stopped playback")
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                logger.debug("Audio session configured for playback")
            } catch {
                logger.error("Failed to configure audio session: \(error.localizedDescription)")
            }
        #endif
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        // Periodic time observer — updates currentTime and duration every 0.5s
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds

                if let currentDuration = self.player.currentItem?.duration,
                    currentDuration.isNumeric, !currentDuration.isIndefinite
                {
                    self.duration = currentDuration.seconds
                }

                self.nowPlayingService.updatePlaybackState(
                    isPlaying: self.isPlaying,
                    currentTime: self.currentTime,
                    duration: self.duration
                )
            }
        }

        // Observe player rate changes for external play/pause (e.g. stalling)
        let rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let newRate = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let playing = newRate > 0
                if self.isPlaying != playing {
                    self.isPlaying = playing
                }
            }
        }
        itemObservers.append(rateObservation)

        // Observe track ending for automatic advancement via async notification stream
        endOfTrackTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime
            ) {
                guard let self else { break }
                guard let item = notification.object as? AVPlayerItem else { continue }
                self.handleTrackEnd(for: item)
            }
        }
    }

    // MARK: - Remote Command Handlers

    private func setupRemoteCommandHandlers() {
        nowPlayingService.onPlay = { [weak self] in self?.resume() }
        nowPlayingService.onPause = { [weak self] in self?.pause() }
        nowPlayingService.onNext = { [weak self] in self?.next() }
        nowPlayingService.onPrevious = { [weak self] in self?.previous() }
        nowPlayingService.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlayingService.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    // MARK: - Player Item Management

    /// Create an AVPlayerItem for the given track using the stream URL resolver.
    private func makePlayerItem(for track: Track) -> AVPlayerItem? {
        guard let resolver = streamURLResolver, let url = resolver(track) else {
            logger.warning("No stream URL available for track: \(track.title)")
            return nil
        }
        let item = AVPlayerItem(url: url)
        playerItemToTrack[item] = track
        return item
    }

    /// Rebuild the AVQueuePlayer's item queue from the current queue state.
    private func rebuildPlayerQueue() {
        player.removeAllItems()
        playerItemToTrack.removeAll()

        guard let currentTrack = queue.currentTrack else { return }

        if let item = makePlayerItem(for: currentTrack) {
            player.insert(item, after: nil)
        } else {
            logger.error("Failed to create player item for current track: \(currentTrack.title)")
        }

        // Preload upcoming tracks for gapless playback
        preloadNextTracks()
    }

    /// Preload the next 1-2 tracks into AVQueuePlayer for gapless transitions.
    private func preloadNextTracks() {
        // Don't preload for repeat-one (same track will replay)
        guard queue.repeatMode != .one else { return }

        let nextIndex = queue.currentIndex + 1
        let endIndex = min(nextIndex + 2, queue.tracks.count)
        guard nextIndex < endIndex else { return }

        for i in nextIndex..<endIndex {
            let track = queue.tracks[i]
            if let item = makePlayerItem(for: track) {
                player.insert(item, after: player.items().last)
            }
        }
    }

    // MARK: - Track Advancement

    /// Handle the end of a track, advancing the queue or repeating as needed.
    private func handleTrackEnd(for item: AVPlayerItem) {
        // Verify this item belongs to us
        guard playerItemToTrack[item] != nil else { return }
        playerItemToTrack.removeValue(forKey: item)

        logger.debug("Track ended, handling advancement")

        // Repeat-one: replay the same track by rebuilding
        if queue.repeatMode == .one {
            rebuildPlayerQueue()
            player.play()
            isPlaying = true
            currentTime = 0
            updateNowPlaying()
            return
        }

        // Advance the queue model
        guard queue.advance() != nil else {
            // Reached the end of the queue without repeat
            logger.info("Reached end of queue")
            isPlaying = false
            currentTime = 0
            duration = 0
            updateNowPlaying()
            return
        }

        // Check if the player already has the next track loaded (gapless transition)
        if let nextItem = player.currentItem, playerItemToTrack[nextItem] != nil {
            // Gapless transition occurred — just preload more tracks
            preloadNextTracks()
        } else {
            // Player doesn't have the next track (e.g., repeat-all wrap-around)
            rebuildPlayerQueue()
            player.play()
        }

        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
    }

    // MARK: - Now Playing

    /// Update the now playing info for the current track.
    private func updateNowPlaying() {
        guard let track = queue.currentTrack else { return }
        let artworkURL = artworkURLResolver?(track)
        nowPlayingService.updateNowPlaying(
            track: track,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            artworkURL: artworkURL
        )
    }

    /// Update duration from the current player item, falling back to track metadata.
    private func updateDuration() {
        if let currentDuration = player.currentItem?.duration,
            currentDuration.isNumeric, !currentDuration.isIndefinite
        {
            duration = currentDuration.seconds
        } else if let trackDuration = queue.currentTrack?.duration {
            duration = trackDuration
        } else {
            duration = 0
        }
    }
}
