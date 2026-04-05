import Models
import Testing

@testable import PlaybackEngine

// MARK: - Test Helpers

private func makeTracks(_ count: Int) -> [Track] {
    (0..<count).map { i in
        Track(id: ItemID("track-\(i)"), title: "Track \(i)")
    }
}

private func makeTrack(id: String, title: String? = nil) -> Track {
    Track(id: ItemID(id), title: title ?? id)
}

// MARK: - PlayQueueTests

@Suite("PlayQueue")
struct PlayQueueTests {

    // MARK: - 1. Initial State

    @Suite("Initial State")
    struct InitialState {

        @Test @MainActor
        func newQueueIsEmpty() {
            let queue = PlayQueue()
            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack == nil)
        }

        @Test @MainActor
        func newQueueHasNoNextOrPrevious() {
            let queue = PlayQueue()
            #expect(queue.hasNext == false)
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func newQueueUpNextIsEmpty() {
            let queue = PlayQueue()
            #expect(queue.upNext.isEmpty)
        }

        @Test @MainActor
        func newQueueDefaultsToRepeatOff() {
            let queue = PlayQueue()
            #expect(queue.repeatMode == .off)
        }

        @Test @MainActor
        func newQueueDefaultsToShuffleDisabled() {
            let queue = PlayQueue()
            #expect(queue.shuffleEnabled == false)
        }
    }

    // MARK: - 2. Load

    @Suite("Load")
    struct Load {

        @Test @MainActor
        func loadTracksPopulatesQueue() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks)

            #expect(queue.tracks.count == 5)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[0].id)
        }

        @Test @MainActor
        func loadWithStartingAtIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 3)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[3].id)
        }

        @Test @MainActor
        func loadWithStartingAtZero() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 0)

            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[0].id)
        }

        @Test @MainActor
        func loadWithStartingAtLastIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks, startingAt: 3)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[3].id)
        }

        @Test @MainActor
        func loadClampsOutOfBoundsIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 100)

            #expect(queue.currentIndex == 2)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }

        @Test @MainActor
        func loadWithEmptyTracksResetsIndex() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(5), startingAt: 3)

            queue.load(tracks: [], startingAt: 5)

            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack == nil)
        }

        @Test @MainActor
        func loadReplacesExistingTracks() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))

            let newTracks = [makeTrack(id: "new-0"), makeTrack(id: "new-1")]
            queue.load(tracks: newTracks)

            #expect(queue.tracks.count == 2)
            #expect(queue.tracks[0].id == ItemID("new-0"))
            #expect(queue.tracks[1].id == ItemID("new-1"))
        }

        @Test @MainActor
        func loadWithShuffleEnabledShufflesTracks() {
            let queue = PlayQueue()
            queue.shuffleEnabled = true

            let tracks = makeTracks(20)
            queue.load(tracks: tracks, startingAt: 5)

            // The current track should be the one at the original startingAt index, now at 0
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[5].id)
            #expect(queue.tracks.count == 20)

            // All original tracks should still be present
            let loadedIDs = Set(queue.tracks.map(\.id))
            let originalIDs = Set(tracks.map(\.id))
            #expect(loadedIDs == originalIDs)
        }

        @Test @MainActor
        func loadSingleTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(1)
            queue.load(tracks: tracks)

            #expect(queue.tracks.count == 1)
            #expect(queue.currentTrack?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)
        }
    }

    // MARK: - 3. Advance (Repeat .off)

    @Suite("Advance - Repeat Off")
    struct AdvanceRepeatOff {

        @Test @MainActor
        func advanceMovesToNextTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            let result = queue.advance()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func advanceThroughAllTracks() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            #expect(queue.advance()?.id == tracks[1].id)
            #expect(queue.advance()?.id == tracks[2].id)
            #expect(queue.advance() == nil)
        }

        @Test @MainActor
        func advanceReturnsNilAtEnd() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            let result = queue.advance()

            #expect(result == nil)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func advanceOnEmptyQueueReturnsNil() {
            let queue = PlayQueue()
            #expect(queue.advance() == nil)
        }

        @Test @MainActor
        func advanceStaysAtEndAfterReachingIt() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(2))

            _ = queue.advance()  // -> track 1
            _ = queue.advance()  // nil, still at 1
            _ = queue.advance()  // nil, still at 1

            #expect(queue.currentIndex == 1)
        }
    }

    // MARK: - 4. Advance (Repeat .all)

    @Suite("Advance - Repeat All")
    struct AdvanceRepeatAll {

        @Test @MainActor
        func advanceWrapsAroundAtEnd() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .all

            _ = queue.advance()  // -> 1
            _ = queue.advance()  // -> 2
            let result = queue.advance()  // wraps -> 0

            #expect(result?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func advanceCyclesMultipleTimes() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks)
            queue.repeatMode = .all

            #expect(queue.advance()?.id == tracks[1].id)  // 0 -> 1
            #expect(queue.advance()?.id == tracks[0].id)  // 1 -> 0 (wrap)
            #expect(queue.advance()?.id == tracks[1].id)  // 0 -> 1
            #expect(queue.advance()?.id == tracks[0].id)  // 1 -> 0 (wrap)
        }
    }

    // MARK: - 5. Advance (Repeat .one)

    @Suite("Advance - Repeat One")
    struct AdvanceRepeatOne {

        @Test @MainActor
        func advanceStaysOnSameTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 1)
            queue.repeatMode = .one

            let result = queue.advance()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func advanceRepeatedlyStaysOnSameTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .one

            for _ in 0..<5 {
                let result = queue.advance()
                #expect(result?.id == tracks[0].id)
                #expect(queue.currentIndex == 0)
            }
        }
    }

    // MARK: - 6. ForceAdvance (Repeat .off)

    @Suite("ForceAdvance - Repeat Off")
    struct ForceAdvanceRepeatOff {

        @Test @MainActor
        func forceAdvanceMovesToNext() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            let result = queue.forceAdvance()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func forceAdvanceReturnsNilAtEnd() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            let result = queue.forceAdvance()

            #expect(result == nil)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func forceAdvanceOnEmptyReturnsNil() {
            let queue = PlayQueue()
            #expect(queue.forceAdvance() == nil)
        }
    }

    // MARK: - 7. ForceAdvance (Repeat .one)

    @Suite("ForceAdvance - Repeat One")
    struct ForceAdvanceRepeatOne {

        @Test @MainActor
        func forceAdvanceSkipsToNextTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .one

            let result = queue.forceAdvance()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func forceAdvanceWrapsAroundAtEnd() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)
            queue.repeatMode = .one

            let result = queue.forceAdvance()

            #expect(result?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func forceAdvanceThroughAllTracksAndWraps() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .one

            #expect(queue.forceAdvance()?.id == tracks[1].id)
            #expect(queue.forceAdvance()?.id == tracks[2].id)
            #expect(queue.forceAdvance()?.id == tracks[0].id)  // wraps
        }
    }

    // MARK: - 8. ForceAdvance (Repeat .all)

    @Suite("ForceAdvance - Repeat All")
    struct ForceAdvanceRepeatAll {

        @Test @MainActor
        func forceAdvanceWrapsAround() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)
            queue.repeatMode = .all

            let result = queue.forceAdvance()

            #expect(result?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func forceAdvanceAdvancesNormally() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .all

            let result = queue.forceAdvance()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }
    }

    // MARK: - 9. GoBack

    @Suite("GoBack")
    struct GoBack {

        @Test @MainActor
        func goBackMovesToPreviousTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            let result = queue.goBack()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func goBackReturnsNilAtBeginningWithRepeatOff() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            let result = queue.goBack()

            #expect(result == nil)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func goBackWrapsWithRepeatAll() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .all

            let result = queue.goBack()

            #expect(result?.id == tracks[2].id)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func goBackDoesNotWrapWithRepeatOne() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .one

            let result = queue.goBack()

            #expect(result == nil)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func goBackOnEmptyReturnsNil() {
            let queue = PlayQueue()
            #expect(queue.goBack() == nil)
        }

        @Test @MainActor
        func goBackThroughAllTracks() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            #expect(queue.goBack()?.id == tracks[1].id)
            #expect(queue.goBack()?.id == tracks[0].id)
            #expect(queue.goBack() == nil)  // at beginning, repeat off
        }

        @Test @MainActor
        func goBackCyclesWithRepeatAll() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks, startingAt: 1)
            queue.repeatMode = .all

            #expect(queue.goBack()?.id == tracks[0].id)  // 1 -> 0
            #expect(queue.goBack()?.id == tracks[1].id)  // 0 -> 1 (wrap)
            #expect(queue.goBack()?.id == tracks[0].id)  // 1 -> 0
        }
    }

    // MARK: - 10. ForceGoBack

    @Suite("ForceGoBack")
    struct ForceGoBack {

        @Test @MainActor
        func forceGoBackMovesToPrevious() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            let result = queue.forceGoBack()

            #expect(result?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func forceGoBackReturnsNilAtBeginningWithRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))

            let result = queue.forceGoBack()

            #expect(result == nil)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func forceGoBackWrapsWithRepeatOne() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .one

            let result = queue.forceGoBack()

            #expect(result?.id == tracks[2].id)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func forceGoBackWrapsWithRepeatAll() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)
            queue.repeatMode = .all

            let result = queue.forceGoBack()

            #expect(result?.id == tracks[2].id)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func forceGoBackOnEmptyReturnsNil() {
            let queue = PlayQueue()
            #expect(queue.forceGoBack() == nil)
        }
    }

    // MARK: - 11. AddNext

    @Suite("AddNext")
    struct AddNext {

        @Test @MainActor
        func addNextInsertsAfterCurrent() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            let newTrack = makeTrack(id: "inserted")
            queue.addNext(newTrack)

            #expect(queue.tracks.count == 4)
            #expect(queue.tracks[1].id == ItemID("inserted"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func addNextPreservesCurrentTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 1)

            let newTrack = makeTrack(id: "inserted")
            queue.addNext(newTrack)

            #expect(queue.currentTrack?.id == tracks[1].id)
            #expect(queue.tracks[2].id == ItemID("inserted"))
        }

        @Test @MainActor
        func addNextToEmptyQueue() {
            let queue = PlayQueue()
            let newTrack = makeTrack(id: "first")
            queue.addNext(newTrack)

            // Inserts at min(0+1, 0) = 0
            #expect(queue.tracks.count == 1)
            #expect(queue.tracks[0].id == ItemID("first"))
        }

        @Test @MainActor
        func addNextMultipleTimes() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks)

            queue.addNext(makeTrack(id: "a"))
            queue.addNext(makeTrack(id: "b"))

            // Both insert at index 1 (after current), so "b" pushes "a" to index 2
            #expect(queue.tracks[0].id == tracks[0].id)
            #expect(queue.tracks[1].id == ItemID("b"))
            #expect(queue.tracks[2].id == ItemID("a"))
            #expect(queue.tracks[3].id == tracks[1].id)
        }

        @Test @MainActor
        func addNextWhenCurrentIsLast() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks, startingAt: 1)

            queue.addNext(makeTrack(id: "appended"))

            #expect(queue.tracks.count == 3)
            #expect(queue.tracks[2].id == ItemID("appended"))
            #expect(queue.currentIndex == 1)
        }
    }

    // MARK: - 12. AddToEnd

    @Suite("AddToEnd")
    struct AddToEnd {

        @Test @MainActor
        func addToEndAppends() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            let newTrack = makeTrack(id: "appended")
            queue.addToEnd(newTrack)

            #expect(queue.tracks.count == 4)
            #expect(queue.tracks.last?.id == ItemID("appended"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func addToEndPreservesCurrentIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            queue.addToEnd(makeTrack(id: "appended"))

            #expect(queue.currentIndex == 2)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }

        @Test @MainActor
        func addToEndOnEmptyQueue() {
            let queue = PlayQueue()
            queue.addToEnd(makeTrack(id: "first"))

            #expect(queue.tracks.count == 1)
            #expect(queue.tracks[0].id == ItemID("first"))
        }

        @Test @MainActor
        func addToEndMultipleTimes() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))

            queue.addToEnd(makeTrack(id: "a"))
            queue.addToEnd(makeTrack(id: "b"))
            queue.addToEnd(makeTrack(id: "c"))

            #expect(queue.tracks.count == 4)
            #expect(queue.tracks[1].id == ItemID("a"))
            #expect(queue.tracks[2].id == ItemID("b"))
            #expect(queue.tracks[3].id == ItemID("c"))
        }
    }

    // MARK: - 13. Remove

    @Suite("Remove")
    struct Remove {

        @Test @MainActor
        func removeBeforeCurrentAdjustsIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 3)

            queue.remove(at: 1)

            #expect(queue.tracks.count == 4)
            #expect(queue.currentIndex == 2)
            #expect(queue.currentTrack?.id == tracks[3].id)
        }

        @Test @MainActor
        func removeAfterCurrentDoesNotAdjustIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 1)

            queue.remove(at: 3)

            #expect(queue.tracks.count == 4)
            #expect(queue.currentIndex == 1)
            #expect(queue.currentTrack?.id == tracks[1].id)
        }

        @Test @MainActor
        func removeAtCurrentClampsIndex() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            queue.remove(at: 2)

            // currentIndex was 2, removed at 2, clamped to min(2, 1) = 1
            #expect(queue.tracks.count == 2)
            #expect(queue.currentIndex == 1)
            #expect(queue.currentTrack?.id == tracks[1].id)
        }

        @Test @MainActor
        func removeCurrentAtBeginning() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            queue.remove(at: 0)

            // currentIndex = min(0, 1) = 0, new track at 0 is former track[1]
            #expect(queue.tracks.count == 2)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[1].id)
        }

        @Test @MainActor
        func removeLastRemainingTrack() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))

            queue.remove(at: 0)

            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack == nil)
        }

        @Test @MainActor
        func removeOutOfBoundsIsNoOp() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            queue.remove(at: 10)
            queue.remove(at: -1)

            #expect(queue.tracks.count == 3)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func removeFromEmptyQueueIsNoOp() {
            let queue = PlayQueue()
            queue.remove(at: 0)

            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func removeAllTracksOneByOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))

            queue.remove(at: 0)  // remove first
            #expect(queue.tracks.count == 2)

            queue.remove(at: 0)  // remove next first
            #expect(queue.tracks.count == 1)

            queue.remove(at: 0)  // remove last
            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack == nil)
        }

        @Test @MainActor
        func removeMultipleBeforeCurrent() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 4)

            queue.remove(at: 0)  // index adjusts 4 -> 3
            queue.remove(at: 0)  // index adjusts 3 -> 2

            #expect(queue.currentIndex == 2)
            #expect(queue.currentTrack?.id == tracks[4].id)
            #expect(queue.tracks.count == 3)
        }
    }

    // MARK: - 14. Move

    @Suite("Move")
    struct Move {

        @Test @MainActor
        func moveCurrentTrackForward() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 1)

            queue.move(from: 1, to: 3)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[1].id)
        }

        @Test @MainActor
        func moveCurrentTrackBackward() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 3)

            queue.move(from: 3, to: 1)

            #expect(queue.currentIndex == 1)
            #expect(queue.currentTrack?.id == tracks[3].id)
        }

        @Test @MainActor
        func moveTrackFromBeforeCurrentToAfter() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            // source < currentIndex && destination >= currentIndex → currentIndex -= 1
            queue.move(from: 0, to: 4)

            #expect(queue.currentIndex == 1)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }

        @Test @MainActor
        func moveTrackFromAfterCurrentToBefore() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            // source > currentIndex && destination <= currentIndex → currentIndex += 1
            queue.move(from: 4, to: 0)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }

        @Test @MainActor
        func moveTrackBetweenNonCurrentPositions() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 0)

            // Both source and destination > currentIndex → no adjustment
            queue.move(from: 3, to: 4)

            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[0].id)
        }

        @Test @MainActor
        func moveSameIndexIsNoOp() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 1)

            queue.move(from: 1, to: 1)

            #expect(queue.currentIndex == 1)
            #expect(queue.tracks.map(\.id) == tracks.map(\.id))
        }

        @Test @MainActor
        func moveOutOfBoundsIsNoOp() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            queue.move(from: 0, to: 10)

            #expect(queue.tracks.count == 3)
            #expect(queue.tracks.map(\.id) == tracks.map(\.id))
        }

        @Test @MainActor
        func movePreservesAllTracks() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks)

            queue.move(from: 0, to: 4)

            let movedIDs = Set(queue.tracks.map(\.id))
            let originalIDs = Set(tracks.map(\.id))
            #expect(movedIDs == originalIDs)
        }

        @Test @MainActor
        func moveFromAfterCurrentToCurrentPosition() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            // source > currentIndex && destination <= currentIndex → currentIndex += 1
            queue.move(from: 4, to: 2)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }

        @Test @MainActor
        func moveFromBeforeCurrentToCurrentPosition() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            // source < currentIndex && destination >= currentIndex → currentIndex -= 1
            queue.move(from: 0, to: 2)

            #expect(queue.currentIndex == 1)
            #expect(queue.currentTrack?.id == tracks[2].id)
        }
    }

    // MARK: - 15. Shuffle

    @Suite("Shuffle")
    struct Shuffle {

        @Test @MainActor
        func toggleShuffleOnKeepsCurrentTrackAtFront() {
            let queue = PlayQueue()
            let tracks = makeTracks(10)
            queue.load(tracks: tracks, startingAt: 5)

            queue.toggleShuffle()

            #expect(queue.shuffleEnabled == true)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[5].id)
        }

        @Test @MainActor
        func toggleShuffleOnPreservesAllTracks() {
            let queue = PlayQueue()
            let tracks = makeTracks(10)
            queue.load(tracks: tracks)

            queue.toggleShuffle()

            let shuffledIDs = Set(queue.tracks.map(\.id))
            let originalIDs = Set(tracks.map(\.id))
            #expect(shuffledIDs == originalIDs)
            #expect(queue.tracks.count == 10)
        }

        @Test @MainActor
        func toggleShuffleOffRestoresOriginalOrder() {
            let queue = PlayQueue()
            let tracks = makeTracks(10)
            queue.load(tracks: tracks, startingAt: 3)

            queue.toggleShuffle()  // enable
            queue.toggleShuffle()  // disable

            #expect(queue.shuffleEnabled == false)
            #expect(queue.tracks.map(\.id) == tracks.map(\.id))
            #expect(queue.currentTrack?.id == tracks[3].id)
            #expect(queue.currentIndex == 3)
        }

        @Test @MainActor
        func toggleShuffleOffPreservesCurrentTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(10)
            queue.load(tracks: tracks, startingAt: 7)

            queue.toggleShuffle()  // on
            #expect(queue.currentTrack?.id == tracks[7].id)

            queue.toggleShuffle()  // off
            #expect(queue.currentTrack?.id == tracks[7].id)
        }

        @Test @MainActor
        func toggleShuffleOnEmptyQueueIsNoOp() {
            let queue = PlayQueue()
            queue.toggleShuffle()

            #expect(queue.shuffleEnabled == true)
            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func toggleShuffleOnSingleTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(1)
            queue.load(tracks: tracks)

            queue.toggleShuffle()

            #expect(queue.tracks.count == 1)
            #expect(queue.currentTrack?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func shuffleEnabledBeforeLoadShufflesOnLoad() {
            let queue = PlayQueue()
            queue.shuffleEnabled = true

            let tracks = makeTracks(20)
            queue.load(tracks: tracks, startingAt: 10)

            // Current track should be the one at startingAt index, placed at 0
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[10].id)
            #expect(queue.tracks.count == 20)
        }
    }

    // MARK: - 16. Cycle Repeat Mode

    @Suite("CycleRepeatMode")
    struct CycleRepeatMode {

        @Test @MainActor
        func cyclesOffToAll() {
            let queue = PlayQueue()
            #expect(queue.repeatMode == .off)

            queue.cycleRepeatMode()

            #expect(queue.repeatMode == .all)
        }

        @Test @MainActor
        func cyclesAllToOne() {
            let queue = PlayQueue()
            queue.repeatMode = .all

            queue.cycleRepeatMode()

            #expect(queue.repeatMode == .one)
        }

        @Test @MainActor
        func cyclesOneToOff() {
            let queue = PlayQueue()
            queue.repeatMode = .one

            queue.cycleRepeatMode()

            #expect(queue.repeatMode == .off)
        }

        @Test @MainActor
        func fullCycle() {
            let queue = PlayQueue()

            queue.cycleRepeatMode()
            #expect(queue.repeatMode == .all)

            queue.cycleRepeatMode()
            #expect(queue.repeatMode == .one)

            queue.cycleRepeatMode()
            #expect(queue.repeatMode == .off)
        }

        @Test @MainActor
        func multipleCycles() {
            let queue = PlayQueue()

            for _ in 0..<3 {
                queue.cycleRepeatMode()
                #expect(queue.repeatMode == .all)
                queue.cycleRepeatMode()
                #expect(queue.repeatMode == .one)
                queue.cycleRepeatMode()
                #expect(queue.repeatMode == .off)
            }
        }
    }

    // MARK: - 17. HasNext / HasPrevious

    @Suite("HasNext and HasPrevious")
    struct HasNextHasPrevious {

        // -- hasNext --

        @Test @MainActor
        func hasNextTrueWhenNotAtEnd() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))
            #expect(queue.hasNext == true)
        }

        @Test @MainActor
        func hasNextFalseAtEndWithRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3), startingAt: 2)
            #expect(queue.hasNext == false)
        }

        @Test @MainActor
        func hasNextTrueAtEndWithRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3), startingAt: 2)
            queue.repeatMode = .all
            #expect(queue.hasNext == true)
        }

        @Test @MainActor
        func hasNextTrueAtEndWithRepeatOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3), startingAt: 2)
            queue.repeatMode = .one
            #expect(queue.hasNext == true)
        }

        @Test @MainActor
        func hasNextFalseWhenEmpty() {
            let queue = PlayQueue()
            #expect(queue.hasNext == false)
        }

        @Test @MainActor
        func hasNextFalseWhenEmptyWithRepeatAll() {
            let queue = PlayQueue()
            queue.repeatMode = .all
            #expect(queue.hasNext == false)
        }

        @Test @MainActor
        func hasNextTrueWithSingleTrackRepeatOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .one
            #expect(queue.hasNext == true)
        }

        @Test @MainActor
        func hasNextFalseWithSingleTrackRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            #expect(queue.hasNext == false)
        }

        @Test @MainActor
        func hasNextTrueWithSingleTrackRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .all
            #expect(queue.hasNext == true)
        }

        // -- hasPrevious --

        @Test @MainActor
        func hasPreviousTrueWhenNotAtBeginning() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3), startingAt: 1)
            #expect(queue.hasPrevious == true)
        }

        @Test @MainActor
        func hasPreviousFalseAtBeginningWithRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func hasPreviousTrueAtBeginningWithRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))
            queue.repeatMode = .all
            #expect(queue.hasPrevious == true)
        }

        @Test @MainActor
        func hasPreviousFalseAtBeginningWithRepeatOne() {
            // repeatMode .one does NOT enable hasPrevious wrapping
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3))
            queue.repeatMode = .one
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func hasPreviousFalseWhenEmpty() {
            let queue = PlayQueue()
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func hasPreviousFalseWithSingleTrackRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func hasPreviousTrueWithSingleTrackRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .all
            #expect(queue.hasPrevious == true)
        }
    }

    // MARK: - 18. UpNext

    @Suite("UpNext")
    struct UpNext {

        @Test @MainActor
        func upNextReturnsTracksAfterCurrent() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 1)

            let upNext = queue.upNext

            #expect(upNext.count == 3)
            #expect(upNext[0].id == tracks[2].id)
            #expect(upNext[1].id == tracks[3].id)
            #expect(upNext[2].id == tracks[4].id)
        }

        @Test @MainActor
        func upNextEmptyAtLastTrack() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            #expect(queue.upNext.isEmpty)
        }

        @Test @MainActor
        func upNextEmptyForEmptyQueue() {
            let queue = PlayQueue()
            #expect(queue.upNext.isEmpty)
        }

        @Test @MainActor
        func upNextWithSingleTrack() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            #expect(queue.upNext.isEmpty)
        }

        @Test @MainActor
        func upNextAtFirstTrackReturnsAllButFirst() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks)

            let upNext = queue.upNext

            #expect(upNext.count == 3)
            #expect(upNext.map(\.id) == [tracks[1].id, tracks[2].id, tracks[3].id])
        }

        @Test @MainActor
        func upNextUpdatesAfterAdvance() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks)

            #expect(queue.upNext.count == 3)

            queue.advance()
            #expect(queue.upNext.count == 2)

            queue.advance()
            #expect(queue.upNext.count == 1)

            queue.advance()
            #expect(queue.upNext.count == 0)
        }

        @Test @MainActor
        func upNextUpdatesAfterAddNext() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks)

            queue.addNext(makeTrack(id: "inserted"))

            #expect(queue.upNext.count == 2)
            #expect(queue.upNext[0].id == ItemID("inserted"))
            #expect(queue.upNext[1].id == tracks[1].id)
        }
    }

    // MARK: - 19. Clear

    @Suite("Clear")
    struct Clear {

        @Test @MainActor
        func clearResetsAllState() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(5), startingAt: 3)
            queue.repeatMode = .all

            queue.clear()

            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack == nil)
            #expect(queue.upNext.isEmpty)
            #expect(queue.hasNext == false)
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func clearOnAlreadyEmptyQueue() {
            let queue = PlayQueue()
            queue.clear()

            #expect(queue.tracks.isEmpty)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func clearDoesNotResetRepeatMode() {
            let queue = PlayQueue()
            queue.repeatMode = .all
            queue.load(tracks: makeTracks(3))

            queue.clear()

            // repeatMode is not touched by clear()
            #expect(queue.repeatMode == .all)
        }

        @Test @MainActor
        func clearDoesNotResetShuffleEnabled() {
            let queue = PlayQueue()
            queue.shuffleEnabled = true
            queue.load(tracks: makeTracks(3))

            queue.clear()

            // shuffleEnabled is not touched by clear()
            #expect(queue.shuffleEnabled == true)
        }

        @Test @MainActor
        func loadAfterClearWorksCorrectly() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(5))
            queue.clear()

            let newTracks = makeTracks(3)
            queue.load(tracks: newTracks)

            #expect(queue.tracks.count == 3)
            #expect(queue.currentTrack?.id == newTracks[0].id)
        }
    }

    // MARK: - 20. Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test @MainActor
        func advanceOnEmptyQueue() {
            let queue = PlayQueue()
            #expect(queue.advance() == nil)
            #expect(queue.forceAdvance() == nil)
            #expect(queue.goBack() == nil)
            #expect(queue.forceGoBack() == nil)
        }

        @Test @MainActor
        func singleTrackAdvanceRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))

            #expect(queue.advance() == nil)
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func singleTrackAdvanceRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .all

            let result = queue.advance()

            #expect(result?.id == ItemID("track-0"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func singleTrackAdvanceRepeatOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .one

            let result = queue.advance()

            #expect(result?.id == ItemID("track-0"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func singleTrackForceAdvanceRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))

            #expect(queue.forceAdvance() == nil)
        }

        @Test @MainActor
        func singleTrackForceAdvanceRepeatOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .one

            let result = queue.forceAdvance()

            #expect(result?.id == ItemID("track-0"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func singleTrackGoBackRepeatOff() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))

            #expect(queue.goBack() == nil)
        }

        @Test @MainActor
        func singleTrackGoBackRepeatAll() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .all

            let result = queue.goBack()

            #expect(result?.id == ItemID("track-0"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func singleTrackForceGoBackRepeatOne() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(1))
            queue.repeatMode = .one

            let result = queue.forceGoBack()

            #expect(result?.id == ItemID("track-0"))
            #expect(queue.currentIndex == 0)
        }

        @Test @MainActor
        func changeRepeatModeAfterReachingEnd() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 2)

            // Can't advance with repeat off
            #expect(queue.advance() == nil)

            // Now enable repeat all
            queue.repeatMode = .all

            // Should be able to advance (wrap)
            let result = queue.advance()
            #expect(result?.id == tracks[0].id)
        }

        @Test @MainActor
        func addNextThenAdvance() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks)

            queue.addNext(makeTrack(id: "inserted"))

            let result = queue.advance()
            #expect(result?.id == ItemID("inserted"))
        }

        @Test @MainActor
        func addToEndThenAdvanceToIt() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks, startingAt: 1)

            queue.addToEnd(makeTrack(id: "appended"))

            let result = queue.advance()
            #expect(result?.id == ItemID("appended"))
        }

        @Test @MainActor
        func removeAndAdvance() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks)  // at 0

            // Remove track at index 1 (the next one in line)
            queue.remove(at: 1)

            // Advancing should skip to what was track[2] (now at index 1)
            let result = queue.advance()
            #expect(result?.id == tracks[2].id)
        }

        @Test @MainActor
        func moveThenAdvance() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks)  // at 0

            // Move track 3 to just after current (position 1)
            queue.move(from: 3, to: 1)

            // Current should still be at 0 (moved from after to after)
            let result = queue.advance()
            #expect(result?.id == tracks[3].id)
        }

        @Test @MainActor
        func twoTrackQueueAdvanceAndGoBack() {
            let queue = PlayQueue()
            let tracks = makeTracks(2)
            queue.load(tracks: tracks)

            #expect(queue.advance()?.id == tracks[1].id)
            #expect(queue.goBack()?.id == tracks[0].id)
            #expect(queue.advance()?.id == tracks[1].id)
        }

        @Test @MainActor
        func shuffleAndAdvanceThroughQueue() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            queue.toggleShuffle()

            // Should be able to advance through all tracks
            var visited = Set<TrackID>()
            visited.insert(queue.currentTrack!.id)

            for _ in 0..<4 {
                let next = queue.advance()
                #expect(next != nil)
                visited.insert(next!.id)
            }

            // All 5 tracks should have been visited
            #expect(visited.count == 5)

            // At the end with repeat off
            #expect(queue.advance() == nil)
        }

        @Test @MainActor
        func removeCurrentTrackInMiddle() {
            let queue = PlayQueue()
            let tracks = makeTracks(5)
            queue.load(tracks: tracks, startingAt: 2)

            queue.remove(at: 2)  // remove current

            // currentIndex clamped to min(2, 3) = 2 → tracks[3]
            #expect(queue.currentIndex == 2)
            #expect(queue.currentTrack?.id == tracks[3].id)
            #expect(queue.tracks.count == 4)
        }

        @Test @MainActor
        func advanceForceAdvanceDifferencesWithRepeatOne() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 0)
            queue.repeatMode = .one

            // auto-advance stays on the same track
            let autoResult = queue.advance()
            #expect(autoResult?.id == tracks[0].id)
            #expect(queue.currentIndex == 0)

            // force-advance skips to next
            let forceResult = queue.forceAdvance()
            #expect(forceResult?.id == tracks[1].id)
            #expect(queue.currentIndex == 1)
        }

        @Test @MainActor
        func goBackForceGoBackDifferencesWithRepeatOne() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks, startingAt: 0)
            queue.repeatMode = .one

            // goBack at index 0 returns nil (repeat .one doesn't wrap for goBack)
            let backResult = queue.goBack()
            #expect(backResult == nil)
            #expect(queue.currentIndex == 0)

            // forceGoBack wraps to end with repeat .one
            let forceResult = queue.forceGoBack()
            #expect(forceResult?.id == tracks[2].id)
            #expect(queue.currentIndex == 2)
        }

        @Test @MainActor
        func loadResetsAdvanceState() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(3), startingAt: 2)
            #expect(queue.advance() == nil)  // at end with .off

            // Loading new tracks should fully reset
            let newTracks = makeTracks(4)
            queue.load(tracks: newTracks)

            #expect(queue.currentIndex == 0)
            #expect(queue.advance()?.id == newTracks[1].id)
        }

        @Test @MainActor
        func shuffleToggleDoesNotAffectRepeatMode() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(5))
            queue.repeatMode = .all

            queue.toggleShuffle()
            #expect(queue.repeatMode == .all)

            queue.toggleShuffle()
            #expect(queue.repeatMode == .all)
        }

        @Test @MainActor
        func hasNextAndHasPreviousAfterOperations() {
            let queue = PlayQueue()
            let tracks = makeTracks(3)
            queue.load(tracks: tracks)

            #expect(queue.hasNext == true)
            #expect(queue.hasPrevious == false)

            _ = queue.advance()  // at 1
            #expect(queue.hasNext == true)
            #expect(queue.hasPrevious == true)

            _ = queue.advance()  // at 2
            #expect(queue.hasNext == false)
            #expect(queue.hasPrevious == true)
        }

        @Test @MainActor
        func addNextOnEmptyThenAdvance() {
            let queue = PlayQueue()
            queue.addNext(makeTrack(id: "a"))
            queue.addNext(makeTrack(id: "b"))

            // "a" was added first (at index 0 of empty), "b" added at min(0+1, 1) = 1
            #expect(queue.tracks.count == 2)

            // currentIndex is still 0, but since we never loaded,
            // currentTrack should be whatever is at index 0
            #expect(queue.currentTrack?.id == ItemID("a"))
        }

        @Test @MainActor
        func operationsAfterClear() {
            let queue = PlayQueue()
            queue.load(tracks: makeTracks(5), startingAt: 2)
            queue.clear()

            #expect(queue.advance() == nil)
            #expect(queue.forceAdvance() == nil)
            #expect(queue.goBack() == nil)
            #expect(queue.forceGoBack() == nil)
            #expect(queue.hasNext == false)
            #expect(queue.hasPrevious == false)
        }

        @Test @MainActor
        func moveFirstToLast() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks, startingAt: 0)

            queue.move(from: 0, to: 3)

            #expect(queue.currentIndex == 3)
            #expect(queue.currentTrack?.id == tracks[0].id)
            #expect(queue.tracks[0].id == tracks[1].id)
        }

        @Test @MainActor
        func moveLastToFirst() {
            let queue = PlayQueue()
            let tracks = makeTracks(4)
            queue.load(tracks: tracks, startingAt: 3)

            queue.move(from: 3, to: 0)

            #expect(queue.currentIndex == 0)
            #expect(queue.currentTrack?.id == tracks[3].id)
        }
    }
}
