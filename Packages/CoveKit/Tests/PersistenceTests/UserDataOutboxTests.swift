import Foundation
import GRDB
import Models
import XCTest

@testable import Persistence

final class UserDataOutboxTests: XCTestCase {
    var db: DatabaseManager!
    var catalog: CatalogRepository!
    var outbox: UserDataOutboxRepository!
    let scope = CatalogRepository.Scope(serverId: "srv", userId: "usr")

    override func setUp() async throws {
        db = try DatabaseManager()
        try await db.dbWriter.write { d in
            try d.execute(sql: "INSERT INTO servers (id, name, url, userId, serverType) VALUES ('srv','S','https://s','usr','jellyfin')")
        }
        catalog = CatalogRepository(database: db)
        outbox = UserDataOutboxRepository(database: db)
        try await catalog.upsert([
            CatalogEntry(id: "a", libraryId: "lib", type: "Movie", mediaType: .movie, name: "A", sortName: "A",
                         dateCreated: Date(timeIntervalSince1970: 1_600_000_000), userData: UserData()),
        ], scope: scope)
    }

    func testEnqueueAppliesLocallyAndQueues() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "a", scope: scope)
        let ud = try await catalog.userData(itemId: "a", scope: scope)
        let pending = try await outbox.pending(scope: scope)
        XCTAssertEqual(ud?.isFavorite, true)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.change.field, "favorite")
    }

    func testSixTogglesCoalesceToOneRowWithTheFinalValue() async throws {
        for i in 0..<6 {
            try await outbox.enqueue(.favorite(i % 2 == 0, at: .now), itemId: "a", scope: scope)
        }
        let pending = try await outbox.pending(scope: scope)
        XCTAssertEqual(pending.count, 1)
        guard case .favorite(let v, _) = pending.first!.change else { return XCTFail("wrong change") }
        XCTAssertEqual(v, false, "final toggle was false")
    }

    func testDifferentFieldsAreSeparateRowsInOrder() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try await outbox.enqueue(.played(true, at: t0.addingTimeInterval(10)), itemId: "a", scope: scope)
        try await outbox.enqueue(.favorite(true, at: t0), itemId: "a", scope: scope)
        let pending = try await outbox.pending(scope: scope)
        XCTAssertEqual(pending.map(\.change.field), ["favorite", "played"], "ordered by when it happened, not when it was queued")
    }

    func testPendingFieldSurvivesASweepUntilRemoved() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "a", scope: scope)
        try await catalog.upsertUserData([("a", UserData(isFavorite: false, isPlayed: true))], scope: scope)   // server says no
        var ud = try await catalog.userData(itemId: "a", scope: scope)
        XCTAssertEqual(ud?.isFavorite, true, "protected while pending")
        XCTAssertEqual(ud?.isPlayed, true, "other fields still updated")

        let id = try await outbox.pending(scope: scope).first!.id
        try await outbox.remove(id: id)
        try await catalog.upsertUserData([("a", UserData(isFavorite: false, isPlayed: true))], scope: scope)
        ud = try await catalog.userData(itemId: "a", scope: scope)
        XCTAssertEqual(ud?.isFavorite, false, "acknowledged → server is the truth again")
    }

    func testPlayedResetsPositionAndBumpsPlayCount() async throws {
        try await catalog.upsertUserData([("a", UserData(playbackPosition: 600))], scope: scope)
        try await outbox.enqueue(.played(true, at: .now), itemId: "a", scope: scope)
        let ud = try await catalog.userData(itemId: "a", scope: scope)
        XCTAssertEqual(ud?.isPlayed, true)
        XCTAssertEqual(ud?.playbackPosition, 0)
        XCTAssertEqual(ud?.playCount, 1)
    }

    func testPositionThatFinishesMarksPlayed() async throws {
        try await outbox.enqueue(.position(ticks: 55_000_000_000, played: true, at: .now), itemId: "a", scope: scope)
        let ud = try await catalog.userData(itemId: "a", scope: scope)
        XCTAssertEqual(ud?.isPlayed, true)
        XCTAssertEqual(ud?.playbackPosition, 0, "a finished item does not keep a resume point")
    }

    func testUnknownItemQueuesButDoesNotCreateAnOrphanRow() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "ghost", scope: scope)
        let ud = try await catalog.userData(itemId: "ghost", scope: scope)
        let count = try await outbox.pendingCount(scope: scope)
        XCTAssertNil(ud)
        XCTAssertEqual(count, 1, "the server still hears about it")
    }

    func testRecordFailureCountsAttempts() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "a", scope: scope)
        let id = try await outbox.pending(scope: scope).first!.id
        try await outbox.recordFailure(id: id, error: "timeout")
        try await outbox.recordFailure(id: id, error: "timeout")
        let attempts = try await outbox.pending(scope: scope).first!.attempts
        XCTAssertEqual(attempts, 2)
    }
}
