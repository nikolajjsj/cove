import Foundation
import Models
import Testing

@testable import PlaybackEngine

// MARK: - Mock Audio Player Backend

@MainActor
final class MockAudioPlayerBackend: AudioPlayerBackend {
    // MARK: - Call Tracking

    var playCallCount = 0
    var pauseCallCount = 0
    var seekCallCount = 0
    var clearQueueCallCount = 0
    var enqueuedURLs: [URL] = []
    var enqueuedTokens: [AnyHashable] = []

    // MARK: - Seek Tracking

    var lastSeekTarget: TimeInterval?
    var seekCompletesSuccessfully = true

    // MARK: - Configurable State

    var _currentItemDuration: TimeInterval?
    private var nextTokenID = 0

    // MARK: - AudioPlayerBackend

    var currentItemDuration: TimeInterval? { _currentItemDuration }

    var currentItemToken: AnyHashable? { enqueuedTokens.first }

    var onTimeUpdate: (@MainActor (TimeInterval) -> Void)?
    var onPlayingChanged: (@MainActor (_ isPlaying: Bool) -> Void)?
    var onItemDidFinish: (@MainActor (_ token: AnyHashable) -> Void)?

    func play() {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func seek(to seconds: TimeInterval, completion: @escaping @Sendable (Bool) -> Void) {
        seekCallCount += 1
        lastSeekTarget = seconds
        completion(seekCompletesSuccessfully)
    }

    func clearQueue() {
        clearQueueCallCount += 1
        enqueuedURLs.removeAll()
        enqueuedTokens.removeAll()
    }

    @discardableResult
    func enqueue(url: URL) -> AnyHashable {
        enqueuedURLs.append(url)
        let token = AnyHashable("token-\(nextTokenID)")
        nextTokenID += 1
        enqueuedTokens.append(token)
        return token
    }

    // MARK: - Simulation Helpers

    func simulateItemFinish() {
        guard let token = enqueuedTokens.first else { return }
        enqueuedTokens.removeFirst()
        if !enqueuedURLs.isEmpty { enqueuedURLs.removeFirst() }
        onItemDidFinish?(token)
    }

    func simulateTimeUpdate(_ time: TimeInterval) {
        onTimeUpdate?(time)
    }

    func simulatePlayingChanged(_ playing: Bool) {
        onPlayingChanged?(playing)
    }
}

// MARK: - Mock Now Playing Provider

@MainActor
final class MockNowPlayingProvider: NowPlayingProvider {
    // MARK: - Call Tracking

    var setupCallCount = 0
    var teardownCallCount = 0
    var updateNowPlayingCallCount = 0
    var updatePlaybackStateCallCount = 0

    // MARK: - Recorded Values

    var lastUpdatedTrack: Track?
    var lastIsPlaying: Bool?
    var lastCurrentTime: TimeInterval?
    var lastDuration: TimeInterval?
    var lastArtworkURL: URL?
    var lastPlaybackStateIsPlaying: Bool?

    // MARK: - Remote Command Callbacks

    var onPlay: (@MainActor () -> Void)?
    var onPause: (@MainActor () -> Void)?
    var onNext: (@MainActor () -> Void)?
    var onPrevious: (@MainActor () -> Void)?
    var onSeek: (@MainActor (TimeInterval) -> Void)?
    var onTogglePlayPause: (@MainActor () -> Void)?

    // MARK: - NowPlayingProvider

    func setup() {
        setupCallCount += 1
    }

    func teardown() {
        teardownCallCount += 1
    }

    func updateNowPlaying(
        track: Track,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        artworkURL: URL?
    ) {
        updateNowPlayingCallCount += 1
        lastUpdatedTrack = track
        lastIsPlaying = isPlaying
        lastCurrentTime = currentTime
        lastDuration = duration
        lastArtworkURL = artworkURL
    }

    func updatePlaybackState(
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) {
        updatePlaybackStateCallCount += 1
        lastPlaybackStateIsPlaying = isPlaying
        lastCurrentTime = currentTime
        lastDuration = duration
    }
}

// MARK: - Test Helpers

private func makeTracks(_ count: Int) -> [Track] {
    (0..<count).map { i in
        Track(id: ItemID("track-\(i)"), title: "Track \(i)")
    }
}

private func makeTracksWithDuration(_ count: Int, duration: TimeInterval = 200) -> [Track] {
    (0..<count).map { i in
        Track(id: ItemID("track-\(i)"), title: "Track \(i)", duration: duration)
    }
}

@MainActor
private func makeManager(
    player: MockAudioPlayerBackend,
    nowPlaying: MockNowPlayingProvider
) -> AudioPlaybackManager {
    let manager = AudioPlaybackManager(playerBackend: player, nowPlayingProvider: nowPlaying)
    manager.streamURLResolver = { track in
        URL(string: "https://example.com/\(track.id.rawValue).mp3")
    }
    return manager
}

// MARK: - AudioPlaybackManagerTests

@Suite("AudioPlaybackManager")
@MainActor
struct AudioPlaybackManagerTests {

    // MARK: - 1. Initialization

    @Suite("Initialization")
    struct Initialization {

        @Test("Initial state is idle")
        @MainActor
        func initialStateIsIdle() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            #expect(manager.isPlaying == false)
            #expect(manager.currentTime == 0)
            #expect(manager.duration == 0)
            #expect(manager.queue.currentTrack == nil)
            #expect(manager.queue.tracks.isEmpty)
        }

        @Test("Setup is called on now playing provider during init")
        @MainActor
        func setupCalledOnInit() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            _ = makeManager(player: player, nowPlaying: nowPlaying)

            #expect(nowPlaying.setupCallCount == 1)
        }
    }

    // MARK: - 2. Play

    @Suite("Play")
    struct Play {

        @Test("play(tracks:) sets isPlaying to true")
        @MainActor
        func playsSetsIsPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(3)
            manager.play(tracks: tracks)

            #expect(manager.isPlaying == true)
        }

        @Test("play(tracks:) calls backend play")
        @MainActor
        func playsCallsBackendPlay() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))

            #expect(player.playCallCount == 1)
        }

        @Test("play(tracks:) enqueues stream URLs via backend")
        @MainActor
        func playsEnqueuesURLs() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(3)
            manager.play(tracks: tracks)

            // Current track + up to 2 preloaded next tracks = 3 total for a 3-track queue starting at 0
            #expect(player.enqueuedURLs.count >= 1)
            #expect(player.enqueuedURLs[0] == URL(string: "https://example.com/track-0.mp3"))
        }

        @Test("play(tracks:) loads tracks into the queue")
        @MainActor
        func playsLoadsQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(5)
            manager.play(tracks: tracks, startingAt: 2)

            #expect(manager.queue.tracks.count == 5)
            #expect(manager.queue.currentIndex == 2)
            #expect(manager.queue.currentTrack?.id == ItemID("track-2"))
        }

        @Test("play(tracks:) resets currentTime to zero")
        @MainActor
        func playsResetsTime() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.currentTime == 0)
        }

        @Test("play(tracks:) updates now playing info")
        @MainActor
        func playsUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(3)
            manager.play(tracks: tracks)

            #expect(nowPlaying.updateNowPlayingCallCount >= 1)
            #expect(nowPlaying.lastUpdatedTrack?.id == ItemID("track-0"))
            #expect(nowPlaying.lastIsPlaying == true)
        }

        @Test("play(tracks:) clears previous queue before enqueuing")
        @MainActor
        func playsClearsPreviousQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            let clearCountAfterFirst = player.clearQueueCallCount

            manager.play(tracks: makeTracks(2))
            #expect(player.clearQueueCallCount > clearCountAfterFirst)
        }

        @Test("play(tracks:) picks up backend duration when available")
        @MainActor
        func playsUsesBackendDuration() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            player._currentItemDuration = 240.0
            manager.play(tracks: makeTracks(2))

            #expect(manager.duration == 240.0)
        }

        @Test("play(tracks:) falls back to track metadata duration")
        @MainActor
        func playsFallsBackToTrackDuration() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            player._currentItemDuration = nil
            manager.play(tracks: makeTracksWithDuration(2, duration: 180))

            #expect(manager.duration == 180.0)
        }

        @Test("play(tracks: startingAt:) starts at the correct index")
        @MainActor
        func playsStartsAtCorrectIndex() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(5)
            manager.play(tracks: tracks, startingAt: 3)

            #expect(manager.queue.currentTrack?.id == ItemID("track-3"))
            #expect(nowPlaying.lastUpdatedTrack?.id == ItemID("track-3"))
        }
    }

    // MARK: - 3. Pause, Resume, Toggle

    @Suite("Pause / Resume / Toggle")
    struct PauseResumeToggle {

        @Test("pause() sets isPlaying false and calls backend pause")
        @MainActor
        func pauseStopsPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()

            #expect(manager.isPlaying == false)
            #expect(player.pauseCallCount == 1)
        }

        @Test("resume() sets isPlaying true when a track is loaded")
        @MainActor
        func resumeSetsPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()
            manager.resume()

            #expect(manager.isPlaying == true)
            // play() called once during play(tracks:) and once during resume()
            #expect(player.playCallCount == 2)
        }

        @Test("resume() does nothing when queue is empty")
        @MainActor
        func resumeDoesNothingWhenEmpty() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.resume()

            #expect(manager.isPlaying == false)
            #expect(player.playCallCount == 0)
        }

        @Test("togglePlayPause() pauses when playing")
        @MainActor
        func togglePausesWhenPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)

            manager.togglePlayPause()
            #expect(manager.isPlaying == false)
        }

        @Test("togglePlayPause() resumes when paused")
        @MainActor
        func toggleResumesWhenPaused() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()
            #expect(manager.isPlaying == false)

            manager.togglePlayPause()
            #expect(manager.isPlaying == true)
        }

        @Test("pause() updates now playing info")
        @MainActor
        func pauseUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            let countBefore = nowPlaying.updateNowPlayingCallCount
            manager.pause()

            #expect(nowPlaying.updateNowPlayingCallCount > countBefore)
            #expect(nowPlaying.lastIsPlaying == false)
        }

        @Test("resume() updates now playing info")
        @MainActor
        func resumeUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()
            let countBefore = nowPlaying.updateNowPlayingCallCount
            manager.resume()

            #expect(nowPlaying.updateNowPlayingCallCount > countBefore)
            #expect(nowPlaying.lastIsPlaying == true)
        }
    }

    // MARK: - 4. Next

    @Suite("Next")
    struct Next {

        @Test("next() advances the queue and starts playing")
        @MainActor
        func nextAdvancesQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            let playCountBefore = player.playCallCount

            manager.next()

            #expect(manager.queue.currentIndex == 1)
            #expect(manager.queue.currentTrack?.id == ItemID("track-1"))
            #expect(manager.isPlaying == true)
            #expect(player.playCallCount > playCountBefore)
        }

        @Test("next() resets currentTime to zero")
        @MainActor
        func nextResetsTime() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            player.simulateTimeUpdate(45.0)
            #expect(manager.currentTime == 45.0)

            manager.next()
            #expect(manager.currentTime == 0)
        }

        @Test("next() rebuilds player queue with new track URLs")
        @MainActor
        func nextRebuildsQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            let clearCountBefore = player.clearQueueCallCount

            manager.next()

            #expect(player.clearQueueCallCount > clearCountBefore)
            // Should have enqueued the new current track URL
            #expect(player.enqueuedURLs.contains(URL(string: "https://example.com/track-1.mp3")!))
        }

        @Test("next() updates now playing to the new track")
        @MainActor
        func nextUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()

            #expect(nowPlaying.lastUpdatedTrack?.id == ItemID("track-1"))
        }

        @Test("next() at end of queue stops playback")
        @MainActor
        func nextAtEndStops() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.next()  // track-1

            // Now at last track
            let pauseCountBefore = player.pauseCallCount
            manager.next()  // no more tracks → stop

            #expect(manager.isPlaying == false)
            #expect(manager.currentTime == 0)
            #expect(manager.duration == 0)
            #expect(manager.queue.tracks.isEmpty)
            #expect(player.pauseCallCount > pauseCountBefore)
        }

        @Test("next() through all tracks sequentially")
        @MainActor
        func nextThroughAllTracks() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(4)
            manager.play(tracks: tracks)

            for i in 1..<4 {
                manager.next()
                #expect(manager.queue.currentTrack?.id == ItemID("track-\(i)"))
                #expect(manager.isPlaying == true)
            }

            // One more next should stop
            manager.next()
            #expect(manager.isPlaying == false)
        }
    }

    // MARK: - 5. Previous

    @Suite("Previous")
    struct Previous {

        @Test("previous() with less than 3 seconds goes to previous track")
        @MainActor
        func previousGoesBackWhenUnder3Seconds() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()  // now at track-1
            #expect(manager.currentTime == 0)  // under 3s

            let playCountBefore = player.playCallCount
            manager.previous()

            #expect(manager.queue.currentIndex == 0)
            #expect(manager.queue.currentTrack?.id == ItemID("track-0"))
            #expect(manager.isPlaying == true)
            #expect(player.playCallCount > playCountBefore)
        }

        @Test("previous() with more than 3 seconds restarts current track")
        @MainActor
        func previousRestartsWhenOver3Seconds() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()  // now at track-1

            // Simulate being more than 3 seconds in
            player.simulateTimeUpdate(10.0)
            #expect(manager.currentTime == 10.0)

            let seekCountBefore = player.seekCallCount
            manager.previous()

            // Should seek to 0 instead of going to previous track
            #expect(player.seekCallCount > seekCountBefore)
            #expect(player.lastSeekTarget == 0)
            #expect(manager.queue.currentIndex == 1)  // stays on same track
        }

        @Test("previous() at beginning of queue does nothing (repeat off)")
        @MainActor
        func previousAtBeginningDoesNothing() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            // currentTime is 0, under 3s, so it tries forceGoBack
            // But we're at index 0, repeat off → forceGoBack returns nil

            let indexBefore = manager.queue.currentIndex
            manager.previous()

            #expect(manager.queue.currentIndex == indexBefore)
        }

        @Test("previous() updates now playing to the previous track")
        @MainActor
        func previousUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()
            manager.next()  // now at track-2

            manager.previous()  // back to track-1

            #expect(nowPlaying.lastUpdatedTrack?.id == ItemID("track-1"))
        }

        @Test("previous() resets currentTime when going back")
        @MainActor
        func previousResetsTimeWhenGoingBack() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()  // track-1, currentTime=0
            player.simulateTimeUpdate(1.5)

            manager.previous()  // back to track-0
            #expect(manager.currentTime == 0)
        }
    }

    // MARK: - 6. Seek

    @Suite("Seek")
    struct Seek {

        @Test("seek() calls backend seek with correct time")
        @MainActor
        func seekCallsBackend() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.seek(to: 42.5)

            #expect(player.seekCallCount == 1)
            #expect(player.lastSeekTarget == 42.5)
        }

        @Test("seek() updates currentTime on successful completion")
        @MainActor
        func seekUpdatesCurrentTime() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            player.seekCompletesSuccessfully = true
            manager.play(tracks: makeTracks(2))
            manager.seek(to: 30.0)

            // The seek completion is called synchronously in our mock
            #expect(manager.currentTime == 30.0)
        }

        @Test("seek() does not update currentTime on failed seek")
        @MainActor
        func seekDoesNotUpdateOnFailure() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            player.seekCompletesSuccessfully = false
            manager.play(tracks: makeTracks(2))
            manager.seek(to: 30.0)

            #expect(manager.currentTime == 0)
        }

        @Test("seek() updates playback state on now playing provider")
        @MainActor
        func seekUpdatesPlaybackState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            let countBefore = nowPlaying.updatePlaybackStateCallCount
            manager.seek(to: 60.0)

            #expect(nowPlaying.updatePlaybackStateCallCount > countBefore)
        }
    }

    // MARK: - 7. Stop

    @Suite("Stop")
    struct Stop {

        @Test("stop() sets isPlaying to false")
        @MainActor
        func stopSetsNotPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.stop()

            #expect(manager.isPlaying == false)
        }

        @Test("stop() resets currentTime and duration")
        @MainActor
        func stopResetsTimeAndDuration() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            player._currentItemDuration = 180.0
            manager.play(tracks: makeTracks(3))
            player.simulateTimeUpdate(45.0)

            manager.stop()

            #expect(manager.currentTime == 0)
            #expect(manager.duration == 0)
        }

        @Test("stop() clears the queue")
        @MainActor
        func stopClearsQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.stop()

            #expect(manager.queue.tracks.isEmpty)
            #expect(manager.queue.currentTrack == nil)
        }

        @Test("stop() calls backend pause and clearQueue")
        @MainActor
        func stopCallsBackendPauseAndClear() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            let pauseBefore = player.pauseCallCount
            let clearBefore = player.clearQueueCallCount

            manager.stop()

            #expect(player.pauseCallCount > pauseBefore)
            #expect(player.clearQueueCallCount > clearBefore)
        }

        @Test("stop() calls teardown on now playing provider")
        @MainActor
        func stopCallsTeardown() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.stop()

            #expect(nowPlaying.teardownCallCount == 1)
        }
    }

    // MARK: - 8. Stream URL Resolver

    @Suite("Stream URL Resolver")
    struct StreamURLResolver {

        @Test("play without stream URL resolver does not crash")
        @MainActor
        func playWithoutResolverDoesNotCrash() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = AudioPlaybackManager(
                playerBackend: player, nowPlayingProvider: nowPlaying)
            // Intentionally NOT setting streamURLResolver

            manager.play(tracks: makeTracks(3))

            // Should not crash, but no URLs should be enqueued
            #expect(player.enqueuedURLs.isEmpty)
            // Manager should still be in "playing" state conceptually
            #expect(manager.isPlaying == true)
        }

        @Test("play enqueues correct URLs from resolver")
        @MainActor
        func playEnqueuesCorrectURLs() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(1))

            #expect(player.enqueuedURLs.count == 1)
            #expect(player.enqueuedURLs[0] == URL(string: "https://example.com/track-0.mp3"))
        }

        @Test("artwork URL resolver is used in now playing updates")
        @MainActor
        func artworkURLResolverIsUsed() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)
            manager.artworkURLResolver = { track in
                URL(string: "https://example.com/art/\(track.id.rawValue).jpg")
            }

            manager.play(tracks: makeTracks(1))

            #expect(nowPlaying.lastArtworkURL == URL(string: "https://example.com/art/track-0.jpg"))
        }

        @Test("nil artwork URL resolver sends nil artwork URL")
        @MainActor
        func nilArtworkResolverSendsNilURL() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)
            manager.artworkURLResolver = nil

            manager.play(tracks: makeTracks(1))

            #expect(nowPlaying.lastArtworkURL == nil)
        }
    }

    // MARK: - 9. Time Update Callback

    @Suite("Time Update Callback")
    struct TimeUpdateCallback {

        @Test("backend onTimeUpdate updates manager currentTime")
        @MainActor
        func timeUpdateUpdatesCurrentTime() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            player.simulateTimeUpdate(25.5)

            #expect(manager.currentTime == 25.5)
        }

        @Test("backend onTimeUpdate updates duration from backend")
        @MainActor
        func timeUpdateUpdatesDuration() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            player._currentItemDuration = 300.0
            player.simulateTimeUpdate(10.0)

            #expect(manager.duration == 300.0)
        }

        @Test("backend onTimeUpdate triggers playback state update on now playing")
        @MainActor
        func timeUpdateTriggersPlaybackStateUpdate() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            let countBefore = nowPlaying.updatePlaybackStateCallCount

            player.simulateTimeUpdate(15.0)

            #expect(nowPlaying.updatePlaybackStateCallCount > countBefore)
        }

        @Test("multiple time updates reflect latest value")
        @MainActor
        func multipleTimeUpdates() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            player.simulateTimeUpdate(5.0)
            #expect(manager.currentTime == 5.0)

            player.simulateTimeUpdate(10.0)
            #expect(manager.currentTime == 10.0)

            player.simulateTimeUpdate(15.5)
            #expect(manager.currentTime == 15.5)
        }
    }

    // MARK: - 10. Track End → Advance

    @Suite("Track End Advance")
    struct TrackEndAdvance {

        @Test("backend onItemDidFinish advances to next track")
        @MainActor
        func itemFinishAdvancesQueue() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            #expect(manager.queue.currentTrack?.id == ItemID("track-0"))

            player.simulateItemFinish()

            #expect(manager.queue.currentTrack?.id == ItemID("track-1"))
            #expect(manager.isPlaying == true)
            #expect(manager.currentTime == 0)
        }

        @Test("backend onItemDidFinish updates now playing for next track")
        @MainActor
        func itemFinishUpdatesNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            player.simulateItemFinish()

            #expect(nowPlaying.lastUpdatedTrack?.id == ItemID("track-1"))
            #expect(nowPlaying.lastIsPlaying == true)
        }

        @Test("sequential track finishes advance through queue")
        @MainActor
        func sequentialFinishesAdvance() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(4))

            player.simulateItemFinish()
            #expect(manager.queue.currentTrack?.id == ItemID("track-1"))

            player.simulateItemFinish()
            #expect(manager.queue.currentTrack?.id == ItemID("track-2"))

            player.simulateItemFinish()
            #expect(manager.queue.currentTrack?.id == ItemID("track-3"))
        }
    }

    // MARK: - 11. Track End → End of Queue

    @Suite("Track End at End of Queue")
    struct TrackEndAtEndOfQueue {

        @Test("onItemDidFinish at last track sets isPlaying false")
        @MainActor
        func finishAtEndStopsPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))

            // Finish track-0 → advance to track-1
            player.simulateItemFinish()
            #expect(manager.isPlaying == true)

            // Finish track-1 → end of queue
            player.simulateItemFinish()
            #expect(manager.isPlaying == false)
            #expect(manager.currentTime == 0)
            #expect(manager.duration == 0)
        }

        @Test("single track queue ends after finish")
        @MainActor
        func singleTrackQueueEndsAfterFinish() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(1))
            #expect(manager.isPlaying == true)

            player.simulateItemFinish()
            #expect(manager.isPlaying == false)
        }
    }

    // MARK: - 12. Now Playing Updates

    @Suite("Now Playing Updates")
    struct NowPlayingUpdates {

        @Test("play(tracks:) calls updateNowPlaying with correct track info")
        @MainActor
        func playCallsUpdateNowPlaying() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            let tracks = makeTracks(3)
            manager.play(tracks: tracks)

            #expect(nowPlaying.lastUpdatedTrack?.title == "Track 0")
            #expect(nowPlaying.lastIsPlaying == true)
            #expect(nowPlaying.lastCurrentTime == 0)
        }

        @Test("pause updates now playing to not playing")
        @MainActor
        func pauseUpdatesNowPlayingState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()

            #expect(nowPlaying.lastIsPlaying == false)
        }

        @Test("resume updates now playing to playing")
        @MainActor
        func resumeUpdatesNowPlayingState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()
            manager.resume()

            #expect(nowPlaying.lastIsPlaying == true)
        }

        @Test("next updates now playing to new track")
        @MainActor
        func nextUpdatesNowPlayingTrack() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.next()

            #expect(nowPlaying.lastUpdatedTrack?.title == "Track 1")
        }

        @Test("stop calls teardown, not updateNowPlaying")
        @MainActor
        func stopCallsTeardownNotUpdate() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            let updateCountAfterPlay = nowPlaying.updateNowPlayingCallCount

            manager.stop()

            // stop() should call teardown, not updateNowPlaying
            #expect(nowPlaying.teardownCallCount == 1)
            // updateNowPlaying should not have been called again
            #expect(nowPlaying.updateNowPlayingCallCount == updateCountAfterPlay)
        }
    }

    // MARK: - 13. Playing Changed Callback

    @Suite("Playing Changed Callback")
    struct PlayingChangedCallback {

        @Test("backend onPlayingChanged updates isPlaying")
        @MainActor
        func playingChangedUpdatesState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)

            // External pause (e.g. audio interruption)
            player.simulatePlayingChanged(false)
            #expect(manager.isPlaying == false)
        }

        @Test("backend onPlayingChanged does not double-set same state")
        @MainActor
        func playingChangedIgnoresDuplicateState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)

            // Simulate backend confirming it's already playing
            player.simulatePlayingChanged(true)
            // Should still be true, no change
            #expect(manager.isPlaying == true)
        }
    }

    // MARK: - 14. Remote Command Handlers

    @Suite("Remote Command Handlers")
    struct RemoteCommandHandlers {

        @Test("now playing onPlay triggers resume")
        @MainActor
        func onPlayTriggersResume() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.pause()
            #expect(manager.isPlaying == false)

            nowPlaying.onPlay?()
            #expect(manager.isPlaying == true)
        }

        @Test("now playing onPause triggers pause")
        @MainActor
        func onPauseTrigersPause() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)

            nowPlaying.onPause?()
            #expect(manager.isPlaying == false)
        }

        @Test("now playing onNext triggers next")
        @MainActor
        func onNextTriggersNext() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            #expect(manager.queue.currentIndex == 0)

            nowPlaying.onNext?()
            #expect(manager.queue.currentIndex == 1)
        }

        @Test("now playing onPrevious triggers previous")
        @MainActor
        func onPreviousTriggersPrevious() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()  // index 1
            #expect(manager.queue.currentIndex == 1)

            nowPlaying.onPrevious?()
            #expect(manager.queue.currentIndex == 0)
        }

        @Test("now playing onTogglePlayPause triggers togglePlayPause")
        @MainActor
        func onTogglePlayPauseTriggersToggle() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)

            nowPlaying.onTogglePlayPause?()
            #expect(manager.isPlaying == false)

            nowPlaying.onTogglePlayPause?()
            #expect(manager.isPlaying == true)
        }

        @Test("now playing onSeek triggers seek")
        @MainActor
        func onSeekTriggersSeek() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            nowPlaying.onSeek?(55.0)

            #expect(player.seekCallCount == 1)
            #expect(player.lastSeekTarget == 55.0)
        }
    }

    // MARK: - 15. Preloading

    @Suite("Preloading")
    struct Preloading {

        @Test("play(tracks:) preloads upcoming tracks")
        @MainActor
        func playPreloadsUpcoming() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))

            // Should enqueue current track + up to 2 preloaded tracks = 3
            #expect(player.enqueuedURLs.count == 3)
            #expect(player.enqueuedURLs[0] == URL(string: "https://example.com/track-0.mp3"))
            #expect(player.enqueuedURLs[1] == URL(string: "https://example.com/track-1.mp3"))
            #expect(player.enqueuedURLs[2] == URL(string: "https://example.com/track-2.mp3"))
        }

        @Test("play(tracks:) with only 1 track does not preload")
        @MainActor
        func singleTrackNoPreload() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(1))

            #expect(player.enqueuedURLs.count == 1)
        }

        @Test("play(tracks:) starting at last track does not preload")
        @MainActor
        func lastTrackNoPreload() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5), startingAt: 4)

            #expect(player.enqueuedURLs.count == 1)
            #expect(player.enqueuedURLs[0] == URL(string: "https://example.com/track-4.mp3"))
        }
    }

    // MARK: - 16. Integration / Complex Scenarios

    @Suite("Integration")
    struct Integration {

        @Test("full playback lifecycle: play, seek, pause, resume, next, stop")
        @MainActor
        func fullLifecycle() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            // 1. Start playing
            manager.play(tracks: makeTracks(3))
            #expect(manager.isPlaying == true)
            #expect(manager.queue.currentTrack?.id == ItemID("track-0"))

            // 2. Simulate time passing
            player.simulateTimeUpdate(30.0)
            #expect(manager.currentTime == 30.0)

            // 3. Seek
            manager.seek(to: 60.0)
            #expect(manager.currentTime == 60.0)

            // 4. Pause
            manager.pause()
            #expect(manager.isPlaying == false)

            // 5. Resume
            manager.resume()
            #expect(manager.isPlaying == true)

            // 6. Next
            manager.next()
            #expect(manager.queue.currentTrack?.id == ItemID("track-1"))
            #expect(manager.currentTime == 0)

            // 7. Stop
            manager.stop()
            #expect(manager.isPlaying == false)
            #expect(manager.queue.tracks.isEmpty)
            #expect(manager.currentTime == 0)
            #expect(manager.duration == 0)
        }

        @Test("re-playing new tracks clears old state")
        @MainActor
        func replayNewTracksClearsOldState() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.next()
            player.simulateTimeUpdate(45.0)

            // Play a completely new set of tracks
            let newTracks = [
                Track(id: ItemID("new-1"), title: "New Track 1"),
                Track(id: ItemID("new-2"), title: "New Track 2"),
            ]
            manager.play(tracks: newTracks)

            #expect(manager.queue.currentTrack?.id == ItemID("new-1"))
            #expect(manager.currentTime == 0)
            #expect(manager.isPlaying == true)
        }

        @Test("pause then play new tracks starts fresh")
        @MainActor
        func pauseThenPlayNewTracks() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(3))
            manager.pause()
            #expect(manager.isPlaying == false)

            let newTracks = makeTracks(2)
            manager.play(tracks: newTracks)
            #expect(manager.isPlaying == true)
            #expect(manager.queue.tracks.count == 2)
        }

        @Test("stop then play starts completely fresh")
        @MainActor
        func stopThenPlay() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(5))
            manager.next()
            manager.next()
            manager.stop()

            #expect(manager.isPlaying == false)
            #expect(manager.queue.tracks.isEmpty)

            manager.play(tracks: makeTracks(2))
            #expect(manager.isPlaying == true)
            #expect(manager.queue.currentTrack?.id == ItemID("track-0"))
            #expect(manager.queue.tracks.count == 2)
        }

        @Test("next through entire queue then play again")
        @MainActor
        func nextThroughThenPlayAgain() {
            let player = MockAudioPlayerBackend()
            let nowPlaying = MockNowPlayingProvider()
            let manager = makeManager(player: player, nowPlaying: nowPlaying)

            manager.play(tracks: makeTracks(2))
            manager.next()  // track-1
            manager.next()  // end → stop

            #expect(manager.isPlaying == false)
            #expect(manager.queue.tracks.isEmpty)

            // Play again
            manager.play(tracks: makeTracks(3))
            #expect(manager.isPlaying == true)
            #expect(manager.queue.tracks.count == 3)
        }
    }
}
