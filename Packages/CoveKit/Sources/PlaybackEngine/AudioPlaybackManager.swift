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

    /// Closure that resolves a Track to a streaming URL. Set by the app layer.
    public var streamURLResolver: (@Sendable (Track) -> URL?)?

    /// Closure that provides artwork URL for a track. Set by the app layer.
    public var artworkURLResolver: (@Sendable (Track) -> URL?)?

    // MARK: - Internal

    private let playerBackend: any AudioPlayerBackend
    private let nowPlaying: any NowPlayingProvider
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "AudioPlayback")

    /// Maps backend item tokens to their corresponding Track for identification.
    @ObservationIgnored private var tokenToTrack: [AnyHashable: Track] = [:]

    /// Whether playback was active before an audio session interruption began.
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false

    /// Task listening for audio session interruption notifications.
    @ObservationIgnored private nonisolated(unsafe) var interruptionTask: Task<Void, Never>?

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
        queue.load(tracks: tracks, startingAt: index)
        rebuildPlayerQueue()
        playerBackend.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
        logger.info("Playing \(tracks.count) tracks, starting at index \(index)")
    }

    /// Resume playback.
    public func resume() {
        guard queue.currentTrack != nil else { return }
        playerBackend.play()
        isPlaying = true
        updateNowPlaying()
        logger.debug("Resumed playback")
    }

    /// Pause playback.
    public func pause() {
        playerBackend.pause()
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
        playerBackend.play()
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
        playerBackend.play()
        isPlaying = true
        currentTime = 0
        updateDuration()
        updateNowPlaying()
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
            }
        }
    }

    /// Stop playback entirely and clear the queue.
    public func stop() {
        playerBackend.pause()
        playerBackend.clearQueue()
        tokenToTrack.removeAll()
        queue.clear()
        isPlaying = false
        currentTime = 0
        duration = 0
        nowPlaying.teardown()
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

    /// Observes `AVAudioSession.interruptionNotification` to pause on interruption
    /// begin (e.g. phone call) and resume when the interruption ends.
    private func setupInterruptionObserver() {
        #if os(iOS)
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
            guard let self else { return }
            self.currentTime = time
            if let backendDuration = self.playerBackend.currentItemDuration {
                self.duration = backendDuration
            }
            self.nowPlaying.updatePlaybackState(
                isPlaying: self.isPlaying,
                currentTime: self.currentTime,
                duration: self.duration
            )
        }

        playerBackend.onPlayingChanged = { [weak self] playing in
            guard let self, self.isPlaying != playing else { return }
            self.isPlaying = playing
        }

        playerBackend.onItemDidFinish = { [weak self] token in
            self?.handleTrackEnd(for: token)
        }
    }

    // MARK: - Remote Command Handlers

    private func setupRemoteCommandHandlers() {
        nowPlaying.onPlay = { [weak self] in self?.resume() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
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

        for i in nextIndex..<endIndex {
            let track = queue.tracks[i]
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
        guard tokenToTrack[token] != nil else { return }
        tokenToTrack.removeValue(forKey: token)

        logger.debug("Track ended, handling advancement")

        // Repeat-one: replay the same track by rebuilding
        if queue.repeatMode == .one {
            rebuildPlayerQueue()
            playerBackend.play()
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
}
