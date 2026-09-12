import AVFoundation
import Models
import XCTest

@testable import PlaybackEngine

/// `VideoPlaybackManager` owns a real `AVPlayer`, which is cheap to construct and
/// needs no window or network as long as nothing is asked to decode — so these
/// drive the manager directly rather than behind a protocol. End-of-item events
/// are delivered by posting the same notifications AVFoundation posts, which
/// exercises the real observer, including its filtering.
@MainActor
final class VideoPlaybackManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(id: String = "item-1", runtimeSeconds: Int64 = 100) -> MediaItem {
        MediaItem(
            id: ItemID(id), title: "Episode", mediaType: .episode,
            runTimeTicks: runtimeSeconds * 10_000_000)
    }

    private func makeStream() -> StreamInfo {
        StreamInfo(url: URL(string: "https://example.com/a.m3u8")!, playMethod: .directPlay)
    }

    /// Let the notification-observing tasks subscribe and drain.
    ///
    /// `NotificationCenter.notifications(named:)` only starts receiving once its
    /// task body has run, so a post issued too soon after `init` is simply missed.
    /// Yields alone do not advance the clock, so this sleeps as well.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<10 { await Task.yield() }
    }

    /// Build a manager and wait until its observers are live.
    private func makeManager() async -> VideoPlaybackManager {
        let manager = VideoPlaybackManager()
        await settle()
        return manager
    }

    /// Poll until `condition` holds or the budget runs out, for work that does
    /// real I/O rather than just suspending.
    private func waitUntil(
        _ condition: () -> Bool, timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Playback speed

    func testSpeedIsClampedToTheSupportedRange() {
        let manager = VideoPlaybackManager()
        manager.setSpeed(9)
        XCTAssertEqual(manager.playbackSpeed, 2.0)
        manager.setSpeed(0.1)
        XCTAssertEqual(manager.playbackSpeed, 0.5)
    }

    func testCyclingSpeedWrapsThroughEveryOption() {
        let manager = VideoPlaybackManager()
        manager.setSpeed(VideoPlaybackManager.speedOptions[0])

        var seen: [Float] = [manager.playbackSpeed]
        for _ in 1..<VideoPlaybackManager.speedOptions.count {
            manager.cycleSpeed()
            seen.append(manager.playbackSpeed)
        }
        XCTAssertEqual(seen, VideoPlaybackManager.speedOptions)

        manager.cycleSpeed()
        XCTAssertEqual(manager.playbackSpeed, VideoPlaybackManager.speedOptions[0], "did not wrap")
    }

    func testCyclingFromAnUnlistedSpeedPicksTheNextOneUp() {
        let manager = VideoPlaybackManager()
        manager.setSpeed(1.1)
        manager.cycleSpeed()
        XCTAssertEqual(manager.playbackSpeed, 1.25)
    }

    // MARK: - Aspect ratio

    func testAspectRatioTogglesBetweenFitAndFill() {
        let manager = VideoPlaybackManager()
        XCTAssertEqual(manager.videoGravity, .resizeAspect)
        manager.cycleAspectRatio()
        XCTAssertEqual(manager.videoGravity, .resizeAspectFill)
        manager.cycleAspectRatio()
        XCTAssertEqual(manager.videoGravity, .resizeAspect)
    }

    // MARK: - Stop reporting

    /// Playback position drives the server's resume point, so a stop must be
    /// reported exactly once per item.
    func testStopIsReportedOnceWhenTheUserDismissesThePlayer() async {
        let manager = await makeManager()
        var stops: [(ItemID, TimeInterval)] = []
        manager.onPlaybackStopped = { item, position in stops.append((item.id, position)) }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        manager.stop()
        await settle()

        XCTAssertEqual(stops.count, 1)
    }

    func testStoppingTwiceStillReportsOnce() async {
        let manager = await makeManager()
        var stops = 0
        manager.onPlaybackStopped = { _, _ in stops += 1 }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        manager.stop()
        manager.stop()
        await settle()

        XCTAssertEqual(stops, 1)
    }

    /// The regression this covers: natural end reported the stop, then auto-play
    /// called loadAndPlay, whose opening stop() reported the *same* item again at
    /// the position playNextEpisode had just reset to 0 — wiping the resume point
    /// for an episode that had in fact been watched to the end.
    func testNaturalEndFollowedByTheNextEpisodeReportsTheFirstItemOnce() async {
        let manager = await makeManager()
        var stops: [(ItemID, TimeInterval)] = []
        manager.onPlaybackStopped = { item, position in stops.append((item.id, position)) }

        manager.loadAndPlay(item: makeItem(id: "episode-1"), streamInfo: makeStream())
        await settle()
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime, object: manager.player.currentItem)
        await settle()

        manager.loadAndPlay(item: makeItem(id: "episode-2"), streamInfo: makeStream())
        await settle()

        XCTAssertEqual(stops.filter { $0.0 == ItemID("episode-1") }.count, 1)
    }

    /// AVFoundation posts AVPlayerItemDidPlayToEndTime for every AVPlayerItem in
    /// the process, the music player's included, so an item that is not ours must
    /// be ignored rather than ending the video.
    func testEndOfItemForAnotherPlayersItemIsIgnored() async {
        let manager = await makeManager()
        var stops = 0
        manager.onPlaybackStopped = { _, _ in stops += 1 }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        await settle()

        let foreignItem = AVPlayerItem(url: URL(string: "https://example.com/music.mp3")!)
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime, object: foreignItem)
        await settle()

        XCTAssertEqual(stops, 0, "another player's item ended our video")
        XCTAssertNotNil(manager.currentItem, "another player's item cleared our state")
    }

    // Note: there is deliberately no "foreign item's *failure* is ignored" test.
    // AVPlayer genuinely fails to load the dummy stream URL these tests use, and
    // that ambient failure races any assertion on an error count. The same guard
    // is covered deterministically by testEndOfItemForAnotherPlayersItemIsIgnored,
    // which asserts on stop reports rather than errors.

    /// A stream that dies mid-playback never reaches its end time, so without this
    /// the player stalls with nothing surfaced to the user.
    func testMidStreamFailureIsSurfacedAsAPlaybackError() async {
        let manager = await makeManager()
        var errors: [ItemID] = []
        manager.onPlaybackError = { item, _ in errors.append(item.id) }

        manager.loadAndPlay(item: makeItem(id: "episode-9"), streamInfo: makeStream())
        await settle()
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime, object: manager.player.currentItem)
        await settle()

        XCTAssertEqual(errors, [ItemID("episode-9")])
    }

    /// A dying stream trips both the item's `.failed` status and the
    /// failed-to-play-to-end notification, so the user must not be told twice.
    func testAFailingStreamIsOnlyReportedOnce() async {
        let manager = await makeManager()
        var errors = 0
        manager.onPlaybackError = { _, _ in errors += 1 }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        await settle()

        for _ in 0..<3 {
            NotificationCenter.default.post(
                name: .AVPlayerItemFailedToPlayToEndTime, object: manager.player.currentItem)
        }
        await settle()

        XCTAssertEqual(errors, 1)
    }

    // MARK: - Loading

    func testLoadingPublishesSubtitleTracksFromTheStream() {
        let manager = VideoPlaybackManager()
        let info = StreamInfo(
            url: URL(string: "https://example.com/a.m3u8")!,
            playMethod: .transcode,
            mediaStreams: [
                MediaStream(index: 2, type: .subtitle, language: "eng", title: "English"),
                MediaStream(index: 3, type: .audio, language: "eng", title: "Stereo"),
            ]
        )

        manager.loadAndPlay(item: makeItem(), streamInfo: info)

        XCTAssertEqual(manager.subtitleTracks.count, 1, "audio track leaked into the subtitle list")
        XCTAssertEqual(manager.subtitleTracks.first?.id, 2)
        XCTAssertEqual(manager.subtitleTracks.first?.title, "English")
    }

    func testLoadingReportsPlaybackStartAtTheResumePosition() async {
        let manager = VideoPlaybackManager()
        var started: [(ItemID, TimeInterval)] = []
        manager.onPlaybackStart = { item, position in started.append((item.id, position)) }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream(), startPosition: 42)
        await settle()

        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.1, 42)
    }

    func testStopClearsPlaybackState() async {
        let manager = VideoPlaybackManager()
        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        manager.setNextEpisode(makeItem(id: "next"))

        manager.stop()
        await settle()

        XCTAssertNil(manager.currentItem)
        XCTAssertNil(manager.nextEpisode)
        XCTAssertTrue(manager.subtitleTracks.isEmpty)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.videoGravity, .resizeAspect)
    }

    // MARK: - Next episode

    func testPlayNextEpisodeHandsOverTheQueuedItemExactlyOnce() async {
        let manager = await makeManager()
        var handedOver: [ItemID] = []
        manager.onPlayNextEpisode = { handedOver.append($0.id) }

        manager.loadAndPlay(item: makeItem(id: "episode-1"), streamInfo: makeStream())
        manager.setNextEpisode(makeItem(id: "episode-2"))

        manager.playNextEpisode()
        manager.playNextEpisode()
        await settle()

        XCTAssertEqual(handedOver, [ItemID("episode-2")])
    }

    func testNaturalEndAutoPlaysTheNextEpisodeWhenOneIsQueued() async {
        let manager = await makeManager()
        var handedOver: [ItemID] = []
        manager.onPlayNextEpisode = { handedOver.append($0.id) }

        manager.loadAndPlay(item: makeItem(id: "episode-1"), streamInfo: makeStream())
        manager.setNextEpisode(makeItem(id: "episode-2"))
        await settle()
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime, object: manager.player.currentItem)
        await settle()

        XCTAssertEqual(handedOver, [ItemID("episode-2")])
    }

    func testNaturalEndWithNoNextEpisodeJustStops() async {
        let manager = await makeManager()
        var handedOver = 0
        manager.onPlayNextEpisode = { _ in handedOver += 1 }

        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        await settle()
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime, object: manager.player.currentItem)
        await settle()

        XCTAssertEqual(handedOver, 0)
        XCTAssertFalse(manager.isPlaying)
    }

    func testDismissingTheCountdownLeavesTheNextEpisodeQueued() {
        let manager = VideoPlaybackManager()
        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())
        manager.setNextEpisode(makeItem(id: "episode-2"))

        manager.dismissNextEpisodeCountdown()

        XCTAssertFalse(manager.showNextEpisodeCountdown)
        XCTAssertNotNil(manager.nextEpisode, "dismissing the prompt discarded the episode")
    }

    // MARK: - Subtitles

    func testSelectingAnExternalSubtitleLoadsAndDisplaysTheCueAtTheCurrentTime() async throws {
        let manager = VideoPlaybackManager()
        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())

        let vtt = """
            WEBVTT

            00:00:00.000 --> 00:00:05.000
            Opening line

            00:00:10.000 --> 00:00:15.000
            Later line
            """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cove-subs-\(UUID().uuidString).vtt")
        try Data(vtt.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        manager.selectSubtitle(at: 0, externalURL: url)
        await waitUntil { manager.currentSubtitleText != nil }

        XCTAssertEqual(manager.currentSubtitleText, "Opening line")
        XCTAssertEqual(manager.selectedSubtitleIndex, 0)
    }

    func testTurningSubtitlesOffClearsTheOverlay() async throws {
        let manager = VideoPlaybackManager()
        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())

        let url = FileManager.default.temporaryDirectory
            .appending(path: "cove-subs-\(UUID().uuidString).vtt")
        try Data("WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nHello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        manager.selectSubtitle(at: 0, externalURL: url)
        await waitUntil { manager.currentSubtitleText != nil }
        XCTAssertNotNil(manager.currentSubtitleText)

        manager.selectSubtitle(at: nil)

        XCTAssertNil(manager.selectedSubtitleIndex)
        XCTAssertNil(manager.currentSubtitleText)
    }

    func testAppendedSubtitleTrackBecomesSelectable() {
        let manager = VideoPlaybackManager()
        manager.loadAndPlay(item: makeItem(), streamInfo: makeStream())

        manager.appendSubtitleTrack(
            SubtitleTrack(id: 99, title: "Downloaded", language: "dan", isExternal: true, url: nil))

        XCTAssertEqual(manager.subtitleTracks.last?.id, 99)
    }
}
