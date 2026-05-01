import AVFoundation
import Foundation
import Models
import os

/// Manages audio playback using an injectable ``AudioPlayerBackend`` with gapless transitions,
/// queue management, and lock screen integration via ``NowPlayingProvider``.
@Observable
@MainActor
public final class AudioPlaybackManager {
    // MARK: - Observable State

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public let queue: PlayQueue = PlayQueue()

    /// The active sleep timer mode, or nil if no timer is set.
    public private(set) var sleepTimerMode: SleepTimerMode?
    /// The date when the sleep timer will fire. Nil if no timer.
    public private(set) var sleepTimerEndDate: Date?
    /// Remaining seconds on the sleep timer.
    public var sleepTimerRemaining: TimeInterval {
        guard let endDate = sleepTimerEndDate else { return 0 }
        return max(endDate.timeIntervalSinceNow, 0)
    }

    /// Closure that resolves a Track to a streaming URL. Set by the app layer.
    public var streamURLResolver: (@Sendable (Track) -> URL?)?

    /// Closure that provides artwork URL for a track. Set by the app layer.
    public var artworkURLResolver: (@Sendable (Track) -> URL?)?

    /// Closure that returns the current favourite state for a track.
    /// Called whenever the Now Playing info is refreshed so the lock screen
    /// heart reflects the live `UserDataStore` value. Set by the app layer.
    public var favoriteStateProvider: (@MainActor @Sendable (Track) -> Bool)?

    /// Called when the user taps the heart button on the lock screen.
    /// The app layer uses this to toggle the favourite via `UserDataStore`
    /// and then call `updateFavoriteState(_:)` with the new value.
    public var onToggleFavorite: (@MainActor (Track) async -> Void)?

    // MARK: - Playback Reporting Callbacks

    /// Called when a track starts playing. The app layer uses this for server reporting.
    public var onPlaybackStart: (@MainActor (Track, TimeInterval) async -> Void)?

    /// Called periodically (~every 10 seconds) during playback, and on pause/seek.
    /// The `Bool` parameter indicates whether playback is paused.
    public var onPlaybackProgress: (@MainActor (Track, TimeInterval, Bool) async -> Void)?

    /// Called when a track stops playing (natural end, skip, or manual stop).
    public var onPlaybackStopped: (@MainActor (Track, TimeInterval) async -> Void)?

    /// Called once per track when the user has listened to at least 95% of it.
    /// The app layer can use this to mark the item as played.
    public var onTrackListened: (@MainActor (Track) async -> Void)?

    // MARK: - Internal

    private let playerBackend: any AudioPlayerBackend
    private let nowPlaying: any NowPlayingProvider
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "AudioPlayback")

    /// Maps backend item tokens to their corresponding Track for identification.
    @ObservationIgnored private var tokenToTrack: [AnyHashable: Track] = [:]

    /// Whether playback was active before an audio session interruption began.
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false

    /// Task running the sleep timer countdown.
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?

    /// Task listening for audio session interruption notifications.
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

    /// Task that periodically reports playback progress to the server.
    @ObservationIgnored private var progressReportTask: Task<Void, Never>?

    /// Set of track IDs for which the 95% "listened" callback has already fired
    /// during the current playback session, to avoid duplicate calls.
    @ObservationIgnored private var listenedTrackIds: Set<TrackID> = []

    // MARK: - Init

    public init(
        playerBackend: (any AudioPlayerBackend)? = nil,
        nowPlayingProvider: (any NowPlayingProvider)? = nil
    ) {
        self.playerBackend = playerBackend ?? AVQueuePlayerBackend()
        self.nowPlaying = nowPlayingProvider ?? NowPlayingService()
        setupAudioSession()
        setupInterruptionObserver()
        setupPlayerCallbacks()
        nowPlaying.setup()
        setupRemoteCommandHandlers()
    }

    // MARK: - Public API

    /// Start playing a list of tracks from a specific index.
    public func play(tracks: [Track], startingAt index: Int = 0) {
        // Report stopped for the previous track if one was playing.
        reportStoppedForCurrentTrack()

        queue.load(tracks: tracks, startingAt: index)
        listenedTrackIds.removeAll()
        rebuildPlayerQueue()
        playerBackend.play()
        isPlaying = true
        nowPlaying.setup()
        setupRemoteCommandHandlers()
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        startProgressReporting()
        reportPlaybackStart()
        logger.info("Playing \(tracks.count) tracks, starting at index \(index)")
    }

    /// Resume playback.
    public func resume() {
        guard queue.currentTrack != nil else { return }
        playerBackend.play()
        isPlaying = true
        updateNowPlaying()
        startProgressReporting()
        reportProgress(isPaused: false)
        logger.debug("Resumed playback")
    }

    /// Pause playback.
    public func pause() {
        playerBackend.pause()
        isPlaying = false
        updateNowPlaying()
        stopProgressReporting()
        reportProgress(isPaused: true)
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
        let previousTrack = queue.currentTrack
        let previousTime = currentTime

        guard queue.forceAdvance() != nil else {
            logger.info("No next track available")
            stop()
            return
        }

        // Report stopped for the track we're leaving.
        reportStopped(track: previousTrack, position: previousTime)

        rebuildPlayerQueue()
        playerBackend.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        reportPlaybackStart()
        logger.info("Skipped to next track: \(self.queue.currentTrack?.title ?? "unknown")")
    }

    /// Jump to a specific index in the queue and start playing.
    public func skipTo(index: Int) {
        let previousTrack = queue.currentTrack
        let previousTime = currentTime

        guard queue.skipTo(index: index) != nil else {
            logger.info("Cannot skip to index \(index) — out of bounds")
            return
        }

        // Report stopped for the track we're leaving.
        reportStopped(track: previousTrack, position: previousTime)

        rebuildPlayerQueue()
        playerBackend.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        reportPlaybackStart()
        logger.info("Skipped to index \(index): \(self.queue.currentTrack?.title ?? "unknown")")
    }

    /// Go to the previous track, or restart the current track if more than 3 seconds in.
    public func previous() {
        if currentTime > 3 {
            seek(to: 0)
            logger.debug("Restarting current track (was \(self.currentTime)s in)")
            return
        }

        let previousTrack = queue.currentTrack
        let previousTime = currentTime

        guard queue.forceGoBack() != nil else {
            logger.info("No previous track available")
            return
        }

        // Report stopped for the track we're leaving.
        reportStopped(track: previousTrack, position: previousTime)

        rebuildPlayerQueue()
        playerBackend.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        reportPlaybackStart()
        logger.info("Went to previous track: \(self.queue.currentTrack?.title ?? "unknown")")
    }

    /// Seek to a specific position in the current track.
    public func seek(to time: TimeInterval) {
        playerBackend.seek(to: time) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time
                self.nowPlaying.updatePlaybackState(
                    isPlaying: self.isPlaying,
                    currentTime: self.currentTime,
                    duration: self.duration
                )
                // Report progress at the new seek position.
                self.reportProgress(isPaused: !self.isPlaying)
                self.checkListenedThreshold()
            }
        }
    }

    /// Start a sleep timer.
    public func setSleepTimer(_ mode: SleepTimerMode) {
        cancelSleepTimer()
        sleepTimerMode = mode

        switch mode {
        case .minutes(let minutes):
            sleepTimerEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            sleepTimerTask = Task { @MainActor [weak self] in
                while let self, let endDate = self.sleepTimerEndDate {
                    guard !Task.isCancelled else { return }
                    if Date.now >= endDate {
                        self.pause()
                        self.cancelSleepTimer()
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        case .endOfTrack:
            sleepTimerEndDate = nil  // No fixed end date
        // The endOfTrack handling is done in handleTrackEnd
        }

        logger.info("Sleep timer set: \(String(describing: mode))")
    }

    /// Cancel any active sleep timer.
    public func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerMode = nil
        sleepTimerEndDate = nil
    }

    /// Propagate a favourite-state change to the lock screen heart button.
    /// Call this after any in-app or lock-screen favourite toggle so the
    /// `MPRemoteCommandCenter.likeCommand.isActive` stays in sync.
    public func updateFavoriteState(isFavorite: Bool) {
        nowPlaying.updateFavoriteState(isFavorite: isFavorite)
    }

    /// Stop playback entirely and clear the queue.
    public func stop() {
        let stoppingTrack = queue.currentTrack
        let stoppingTime = currentTime

        playerBackend.pause()
        playerBackend.clearQueue()
        tokenToTrack.removeAll()
        stopProgressReporting()

        // Report stopped for the track that was playing.
        reportStopped(track: stoppingTrack, position: stoppingTime)

        queue.clear()
        listenedTrackIds.removeAll()
        isPlaying = false
        currentTime = 0
        duration = 0
        nowPlaying.teardown()
        logger.info("Stopped playback")
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        #if !os(macOS)
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

    /// Observes `AVAudioSession.interruptionNotification` to pause on interruption
    /// begin (e.g. phone call) and resume when the interruption ends.
    private func setupInterruptionObserver() {
        #if !os(macOS)
            interruptionTask = Task { [weak self] in
                let notifications = NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification
                )
                for await notification in notifications {
                    guard let self else { break }
                    guard let info = notification.userInfo,
                        let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                        let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                    else {
                        continue
                    }

                    switch type {
                    case .began:
                        self.wasPlayingBeforeInterruption = self.isPlaying
                        if self.isPlaying {
                            self.pause()
                            self.logger.info("Playback paused due to audio session interruption")
                        }
                    case .ended:
                        let shouldResume: Bool
                        if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                            shouldResume = AVAudioSession.InterruptionOptions(
                                rawValue: optionsValue
                            )
                            .contains(.shouldResume)
                        } else {
                            shouldResume = false
                        }

                        if self.wasPlayingBeforeInterruption && shouldResume {
                            self.resume()
                            self.logger.info("Playback resumed after audio session interruption")
                        }
                        self.wasPlayingBeforeInterruption = false
                    @unknown default:
                        break
                    }
                }
            }
        #endif
    }

    // MARK: - Player Callbacks

    private func setupPlayerCallbacks() {
        playerBackend.onTimeUpdate = { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard time.isFinite, time >= 0 else { return }
                self.currentTime = time
                if let backendDuration = self.playerBackend.currentItemDuration {
                    self.duration = backendDuration
                }
                self.nowPlaying.updatePlaybackState(
                    isPlaying: self.isPlaying,
                    currentTime: self.currentTime,
                    duration: self.duration
                )
                self.checkListenedThreshold()
            }
        }

        playerBackend.onPlayingChanged = { [weak self] playing in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying != playing else { return }
                self.isPlaying = playing
            }
        }

        playerBackend.onItemDidFinish = { [weak self] token in
            Task { @MainActor [weak self] in
                self?.handleTrackEnd(for: token)
            }
        }
    }

    // MARK: - Remote Command Handlers

    private func setupRemoteCommandHandlers() {
        nowPlaying.onPlay = { [weak self] in Task { @MainActor [weak self] in self?.resume() } }
        nowPlaying.onPause = { [weak self] in Task { @MainActor [weak self] in self?.pause() } }
        nowPlaying.onNext = { [weak self] in Task { @MainActor [weak self] in self?.next() } }
        nowPlaying.onPrevious = { [weak self] in Task { @MainActor [weak self] in self?.previous() }
        }
        nowPlaying.onTogglePlayPause = { [weak self] in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
        }
        nowPlaying.onSeek = { [weak self] time in
            Task { @MainActor [weak self] in self?.seek(to: time) }
        }
        nowPlaying.onToggleFavorite = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let track = self.queue.currentTrack else { return }
                await self.onToggleFavorite?(track)
            }
        }
    }

    // MARK: - Stream URL Resolution

    /// Resolve a streaming URL for the given track using the stream URL resolver.
    private func resolveStreamURL(for track: Track) -> URL? {
        guard let resolver = streamURLResolver else {
            logger.warning("No stream URL resolver set")
            return nil
        }
        return resolver(track)
    }

    // MARK: - Queue Management

    /// Rebuild the backend's item queue from the current queue state.
    private func rebuildPlayerQueue() {
        playerBackend.clearQueue()
        tokenToTrack.removeAll()

        guard let currentTrack = queue.currentTrack else { return }

        if let url = resolveStreamURL(for: currentTrack) {
            let token = playerBackend.enqueue(url: url)
            tokenToTrack[token] = currentTrack
        } else {
            logger.error("Failed to resolve stream URL for current track: \(currentTrack.title)")
        }

        // Preload upcoming tracks for gapless playback
        preloadNextTracks()
    }

    /// Preload the next 1-2 tracks into the backend for gapless transitions.
    private func preloadNextTracks() {
        // Don't preload for repeat-one (same track will replay)
        guard queue.repeatMode != .one else { return }

        let nextIndex = queue.currentIndex + 1
        let endIndex = min(nextIndex + 2, queue.tracks.count)
        guard nextIndex < endIndex else { return }

        let enqueuedTrackIds = Set(tokenToTrack.values.map(\.id))

        for i in nextIndex..<endIndex {
            let track = queue.tracks[i]
            guard !enqueuedTrackIds.contains(track.id) else { continue }
            if let url = resolveStreamURL(for: track) {
                let token = playerBackend.enqueue(url: url)
                tokenToTrack[token] = track
            }
        }
    }

    // MARK: - Track Advancement

    /// Handle the end of a track, advancing the queue or repeating as needed.
    private func handleTrackEnd(for token: AnyHashable) {
        // Verify this token belongs to us
        let finishedTrack = tokenToTrack[token]
        guard finishedTrack != nil else { return }
        tokenToTrack.removeValue(forKey: token)

        logger.debug("Track ended, handling advancement")

        // Report stopped for the finished track using its full duration
        // so the server registers it as fully played.
        if let track = finishedTrack {
            let trackDuration = track.duration ?? duration
            reportStopped(track: track, position: trackDuration)
        }

        // Check if sleep timer should stop playback at end of track
        if sleepTimerMode == .endOfTrack {
            cancelSleepTimer()
            isPlaying = false
            currentTime = 0
            duration = 0
            stopProgressReporting()
            updateNowPlaying()
            logger.info("Sleep timer: paused at end of track")
            return
        }

        // Repeat-one: replay the same track by rebuilding
        if queue.repeatMode == .one {
            rebuildPlayerQueue()
            playerBackend.play()
            isPlaying = true
            currentTime = 0
            updateNowPlaying()
            reportPlaybackStart()
            return
        }

        // Advance the queue model
        guard queue.advance() != nil else {
            // Reached the end of the queue without repeat
            logger.info("Reached end of queue")
            isPlaying = false
            currentTime = 0
            duration = 0
            stopProgressReporting()
            updateNowPlaying()
            return
        }

        // Check if the backend already has the next track loaded (gapless transition)
        if let currentToken = playerBackend.currentItemToken, tokenToTrack[currentToken] != nil {
            // Gapless transition occurred — just preload more tracks
            preloadNextTracks()
        } else {
            // Backend doesn't have the next track (e.g., repeat-all wrap-around)
            rebuildPlayerQueue()
            playerBackend.play()
        }

        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        reportPlaybackStart()
    }

    // MARK: - Now Playing

    /// Update the now playing info for the current track.
    private func updateNowPlaying() {
        guard let track = queue.currentTrack else { return }
        let artworkURL = artworkURLResolver?(track)
        nowPlaying.updateNowPlaying(
            track: track,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            artworkURL: artworkURL
        )
        // Sync the lock screen heart with the current favourite state.
        let isFav = favoriteStateProvider?(track) ?? false
        nowPlaying.updateFavoriteState(isFavorite: isFav)
    }

    /// Update duration from the backend, falling back to track metadata.
    private func updateDuration() {
        if let backendDuration = playerBackend.currentItemDuration {
            duration = backendDuration
        } else if let trackDuration = queue.currentTrack?.duration {
            duration = trackDuration
        } else {
            duration = 0
        }
    }

    // MARK: - Playback Reporting

    /// Start the periodic progress reporting timer (~every 10 seconds).
    private func startProgressReporting() {
        stopProgressReporting()
        progressReportTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                guard let self, let track = self.queue.currentTrack, self.isPlaying else {
                    continue
                }
                await self.onPlaybackProgress?(track, self.currentTime, false)
            }
        }
    }

    /// Stop the periodic progress reporting timer.
    private func stopProgressReporting() {
        progressReportTask?.cancel()
        progressReportTask = nil
    }

    /// Report playback start for the current track.
    private func reportPlaybackStart() {
        guard let track = queue.currentTrack else { return }
        let position = currentTime
        Task { [weak self] in
            await self?.onPlaybackStart?(track, position)
        }
    }

    /// Report a progress update for the current track.
    private func reportProgress(isPaused: Bool) {
        guard let track = queue.currentTrack else { return }
        let position = currentTime
        Task { [weak self] in
            await self?.onPlaybackProgress?(track, position, isPaused)
        }
    }

    /// Report playback stopped for a specific track at a given position.
    private func reportStopped(track: Track?, position: TimeInterval) {
        guard let track else { return }
        Task { [weak self] in
            await self?.onPlaybackStopped?(track, position)
        }
    }

    /// Report stopped for whatever track is currently playing (convenience for transitions).
    private func reportStoppedForCurrentTrack() {
        reportStopped(track: queue.currentTrack, position: currentTime)
    }

    /// Check whether the current track has reached the 95% listened threshold
    /// and fire the `onTrackListened` callback exactly once per track.
    private func checkListenedThreshold() {
        guard let track = queue.currentTrack,
            !listenedTrackIds.contains(track.id),
            duration > 0,
            currentTime / duration >= 0.95
        else { return }

        listenedTrackIds.insert(track.id)
        logger.info("Track listened (95%%): \(track.title)")
        Task { [weak self] in
            await self?.onTrackListened?(track)
        }
    }
}
