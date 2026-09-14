import Foundation
import MediaServerKit
import Models
import Persistence
import XCTest

@testable import CatalogSync

/// A server that remembers what it was told and fails on command.
final class FakeUserDataWriter: UserDataWriter, @unchecked Sendable {
    var played: [String: (Bool, Date)] = [:]
    var favorites: [String: Bool] = [:]
    var positions: [String: (ticks: Int64, played: Bool)] = [:]
    var calls: [String] = []
    /// itemId → error to throw on any write for it.
    var failures: [String: any Error] = [:]

    func writePlayed(itemId: String, isPlayed: Bool, at date: Date) async throws {
        calls.append("played:\(itemId)")
        if let e = failures[itemId] { throw e }
        played[itemId] = (isPlayed, date)
    }
    func writeFavorite(itemId: String, isFavorite: Bool) async throws {
        calls.append("favorite:\(itemId)")
        if let e = failures[itemId] { throw e }
        favorites[itemId] = isFavorite
    }
    func writePosition(itemId: String, ticks: Int64, played: Bool, at date: Date) async throws {
        calls.append("position:\(itemId)")
        if let e = failures[itemId] { throw e }
        positions[itemId] = (ticks, played)
    }
    func currentPosition(itemId: String) async throws -> (ticks: Int64, played: Bool) {
        positions[itemId] ?? (0, false)
    }
}

final class OutboxFlusherTests: XCTestCase {
    var db: DatabaseManager!
    var catalog: CatalogRepository!
    var outbox: UserDataOutboxRepository!
    var writer: FakeUserDataWriter!
    var flusher: OutboxFlusher!
    let scope = CatalogRepository.Scope(serverId: "srv", userId: "usr")

    override func setUp() async throws {
        db = try DatabaseManager()
        try await db.dbWriter.write { d in
            try d.execute(sql: "INSERT INTO servers (id, name, url, userId, serverType) VALUES ('srv','S','https://s','usr','jellyfin')")
        }
        catalog = CatalogRepository(database: db)
        outbox = UserDataOutboxRepository(database: db)
        writer = FakeUserDataWriter()
        flusher = OutboxFlusher(outbox: outbox, writer: writer, scope: scope)
        try await catalog.upsert(["a", "b", "c"].map {
            CatalogEntry(id: $0, libraryId: "lib", type: "Movie", mediaType: .movie, name: $0, sortName: $0,
                         dateCreated: Date(timeIntervalSince1970: 1_600_000_000), userData: UserData())
        }, scope: scope)
    }

    func testReplaysInOrderAndClearsTheQueue() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await outbox.enqueue(.favorite(true, at: t.addingTimeInterval(2)), itemId: "b", scope: scope)
        try await outbox.enqueue(.played(true, at: t), itemId: "a", scope: scope)
        let out = await flusher.flush()
        let left = try await outbox.pendingCount(scope: scope)
        XCTAssertEqual(writer.calls, ["played:a", "favorite:b"], "order of occurrence, not of enqueue")
        XCTAssertEqual(out.sent, 2)
        XCTAssertEqual(left, 0)
        XCTAssertEqual(writer.played["a"]?.1, t, "the server is told when it was watched")
    }

    func testDeletedItemIsDroppedAndTheQueueContinues() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "a", scope: scope)
        try await outbox.enqueue(.favorite(true, at: .now.addingTimeInterval(1)), itemId: "b", scope: scope)
        writer.failures["a"] = AppError.serverError(statusCode: 404, message: "gone")
        let out = await flusher.flush()
        let left = try await outbox.pendingCount(scope: scope)
        XCTAssertEqual(out.dropped, 1)
        XCTAssertEqual(out.sent, 1)
        XCTAssertEqual(left, 0, "a 404 never blocks what is behind it")
    }

    func testTransientFailureKeepsTheRowAndStopsAfterThree() async throws {
        for (i, id) in ["a", "b", "c"].enumerated() {
            try await outbox.enqueue(.favorite(true, at: .now.addingTimeInterval(Double(i))), itemId: id, scope: scope)
            writer.failures[id] = AppError.networkUnavailable
        }
        let out = await flusher.flush()
        let pending = try await outbox.pending(scope: scope)
        XCTAssertEqual(out.failed, 3)
        XCTAssertTrue(out.stoppedEarly)
        XCTAssertEqual(pending.count, 3, "nothing is lost")
        XCTAssertEqual(pending.map(\.attempts), [1, 1, 1])
    }

    func testAuthFailureStopsWithoutConsumingAnything() async throws {
        try await outbox.enqueue(.favorite(true, at: .now), itemId: "a", scope: scope)
        try await outbox.enqueue(.favorite(true, at: .now.addingTimeInterval(1)), itemId: "b", scope: scope)
        writer.failures["a"] = AppError.authExpired(serverName: "s")
        let out = await flusher.flush()
        let left = try await outbox.pendingCount(scope: scope)
        XCTAssertTrue(out.stoppedEarly)
        XCTAssertEqual(left, 2)
        XCTAssertEqual(writer.calls, ["favorite:a"], "did not even try b")
    }

    func testPositionYieldsToAFurtherServerPosition() async throws {
        writer.positions["a"] = (ticks: 60 * 600_000_000, played: false)             // server: 60 min
        try await outbox.enqueue(.position(ticks: 40 * 600_000_000, played: false, at: .now), itemId: "a", scope: scope)   // phone: 40 min
        let out = await flusher.flush()
        XCTAssertEqual(out.yielded, 1)
        XCTAssertEqual(writer.positions["a"]?.ticks, 60 * 600_000_000, "server untouched")
        XCTAssertFalse(writer.calls.contains("position:a"))
    }

    func testPositionOverwritesALesserServerPosition() async throws {
        writer.positions["a"] = (ticks: 10 * 600_000_000, played: false)
        try await outbox.enqueue(.position(ticks: 40 * 600_000_000, played: false, at: .now), itemId: "a", scope: scope)
        let out = await flusher.flush()
        XCTAssertEqual(out.sent, 1)
        XCTAssertEqual(writer.positions["a"]?.ticks, 40 * 600_000_000)
    }

    func testFinishedPositionWinsEvenIfServerIsFurther() async throws {
        writer.positions["a"] = (ticks: 60 * 600_000_000, played: false)
        try await outbox.enqueue(.position(ticks: 0, played: true, at: .now), itemId: "a", scope: scope)
        let out = await flusher.flush()
        XCTAssertEqual(out.sent, 1)
        XCTAssertEqual(writer.positions["a"]?.played, true, "you cannot un-finish by having watched less")
    }
}
