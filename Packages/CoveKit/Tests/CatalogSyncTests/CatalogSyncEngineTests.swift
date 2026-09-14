import Foundation
import MediaServerKit
import Models
import Persistence
import XCTest

@testable import CatalogSync

final class CatalogSyncEngineTests: XCTestCase {
    var db: DatabaseManager!
    var repo: CatalogRepository!
    var source: FakeCatalogSource!
    var engine: CatalogSyncEngine!
    let scope = CatalogRepository.Scope(serverId: "srv", userId: "usr")
    let library = CatalogSyncEngine.Library(id: Fixture.library, name: "Movies", itemTypes: ["Movie"])

    override func setUp() async throws {
        db = try DatabaseManager()
        // catalog_items has an FK to servers.
        try await db.dbWriter.write { d in
            try d.execute(
                sql: "INSERT INTO servers (id, name, url, userId, serverType) VALUES ('srv','S','https://s','usr','jellyfin')")
        }
        repo = CatalogRepository(database: db)
        source = FakeCatalogSource()
        engine = CatalogSyncEngine(source: source, repository: repo, scope: scope, pageSize: 3)
    }

    // MARK: Bootstrap

    func testBootstrapPagesEverythingAndRecordsCursorFromServerClock() async throws {
        for n in 1...7 { source.add(Fixture.movie(n)) }
        source.serverClock = Date(timeIntervalSince1970: 1_700_000_000)

        await engine.syncIfNeeded(libraries: [library])

        let count = try await repo.count(libraryId: library.id, scope: scope)
        XCTAssertEqual(count, 7)
        let state = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")
        XCTAssertTrue(state.bootstrapComplete)
        // Cursor is the server's clock, not ours.
        XCTAssertEqual(state.cursor, source.serverClock)
        XCTAssertGreaterThan(state.cursor!.timeIntervalSinceNow.magnitude, 60, "cursor must not be device time")
    }

    func testBootstrapIsResumableFromCommittedIndex() async throws {
        for n in 1...5 { source.add(Fixture.movie(n)) }
        // Pretend a prior run committed the first page and died.
        var state = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")
        state.bootstrapNextIndex = 3
        state.cursor = Date(timeIntervalSince1970: 1_699_000_000)  // earliest clock reading
        try await repo.saveSyncState(state)
        try await repo.upsert([1, 2, 3].map { Fixture.movie($0) }, scope: scope)

        await engine.syncIfNeeded(libraries: [library])

        let count = try await repo.count(libraryId: library.id, scope: scope)
        XCTAssertEqual(count, 5)
        let after = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")
        // The earliest reading survives a resume; a later one would open a gap.
        XCTAssertEqual(after.cursor, Date(timeIntervalSince1970: 1_699_000_000))
        XCTAssertEqual(source.pageRequests, 1, "only the unfinished page is fetched")
    }

    // MARK: Delta

    func testDeltaUpsertsOnlyChangedAndAdvancesCursorToNewServerTime() async throws {
        for n in 1...4 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])

        // Time passes on the server; one item is edited, one added.
        source.serverClock = source.serverClock.addingTimeInterval(3600)
        source.add(Fixture.movie(2, name: "Renamed"), savedAt: source.serverClock)
        source.add(Fixture.movie(9), savedAt: source.serverClock)

        await engine.syncIfNeeded(libraries: [library])

        let renamed = try await repo.item(id: "m2", scope: scope)
        let count = try await repo.count(libraryId: library.id, scope: scope)
        XCTAssertEqual(renamed?.title, "Renamed")
        XCTAssertEqual(count, 5)
        let state = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")
        XCTAssertEqual(state.cursor, source.serverClock)
    }

    func testDeltaCursorDoesNotAdvanceWhenALaterPageFails() async throws {
        for n in 1...2 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])
        let before = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")

        source.serverClock = source.serverClock.addingTimeInterval(3600)
        for n in 10...16 { source.add(Fixture.movie(n), savedAt: source.serverClock) }  // 7 changes = 3 pages
        source.failChangesOnPage = 1

        await engine.syncIfNeeded(libraries: [library])

        let after = try await repo.syncState(scope: scope, key: "catalog:\(library.id)")
        XCTAssertEqual(after.cursor, before.cursor, "a failed pass must not move the cursor")
        let status = await engine.status
        XCTAssertEqual(status, .failed(AppError.serverUnreachable(url: URL(string: "https://fake")!).localizedDescription))

        // The next run picks everything up.
        await engine.syncIfNeeded(libraries: [library])
        let count = try await repo.count(libraryId: library.id, scope: scope)
        let cursor = try await repo.syncState(scope: scope, key: "catalog:\(library.id)").cursor
        XCTAssertEqual(count, 9)
        XCTAssertEqual(cursor, source.serverClock)
    }

    func testDeltaOverlapCatchesEditsAtTheCursorBoundary() async throws {
        source.add(Fixture.movie(1))
        await engine.syncIfNeeded(libraries: [library])
        let cursor = try await repo.syncState(scope: scope, key: "catalog:\(library.id)").cursor!

        // Saved 30 s *before* the cursor — inside the overlap window, outside a naive ">= cursor".
        source.add(Fixture.movie(1, name: "Boundary"), savedAt: cursor.addingTimeInterval(-30))
        await engine.syncIfNeeded(libraries: [library])
        let title = try await repo.item(id: "m1", scope: scope)?.title
        XCTAssertEqual(title, "Boundary")
    }

    // MARK: Reconcile — both directions

    func testReconcileRemovesPhantomsAndBackfillsMissing() async throws {
        for n in 1...4 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])

        source.remove("m3")                       // deleted upstream → phantom locally
        source.add(Fixture.movie(8))              // exists upstream, never seen → missing locally
        try await repo.upsert([Fixture.movie(99)], scope: scope)  // local row server never had

        await engine.reconcileAll(libraries: [library])

        let ids = try await repo.itemIds(libraryId: library.id, scope: scope)
        XCTAssertEqual(ids, ["m1", "m2", "m4", "m8"])
        XCTAssertEqual(source.entryRequests, [["m8"]], "backfill fetches exactly the missing ids")
    }

    func testReconcileStampsSeenRows() async throws {
        for n in 1...2 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])   // bootstrap runs a reconcile
        let stamped = try await db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM catalog_items WHERE lastSeenInReconcile IS NOT NULL") ?? 0
        }
        XCTAssertEqual(stamped, 2)
    }

    func testReconciliationDiffIsPure() {
        let out = Reconciliation.diff(server: ["a", "b", "c"], local: ["b", "c", "d"])
        XCTAssertEqual(out.missing, ["a"])
        XCTAssertEqual(out.phantoms, ["d"])
    }

    // MARK: Error classes

    func testErrorClassification() {
        XCTAssertEqual(SyncErrorClass.classify(AppError.networkUnavailable), .transient)
        XCTAssertEqual(SyncErrorClass.classify(AppError.authExpired(serverName: "s")), .auth)
        XCTAssertEqual(SyncErrorClass.classify(AppError.serverError(statusCode: 404, message: nil)), .permanentItem)
        XCTAssertEqual(SyncErrorClass.classify(AppError.serverError(statusCode: 400, message: nil)), .permanentPass)
        XCTAssertEqual(SyncErrorClass.classify(AppError.serverError(statusCode: 503, message: nil)), .transient)
        XCTAssertEqual(SyncErrorClass.classify(AppError.serverError(statusCode: 429, message: nil)), .transient)
    }

    // MARK: Library shapes

    func testItemTypesPerCollection() {
        XCTAssertEqual(CatalogSyncEngine.itemTypes(for: .movies), ["Movie"])
        XCTAssertEqual(CatalogSyncEngine.itemTypes(for: .tvshows), ["Series", "Season", "Episode"])
        XCTAssertNil(CatalogSyncEngine.itemTypes(for: .music))
    }
}
