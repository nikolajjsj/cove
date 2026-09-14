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

    // MARK: User-data sweeps

    func testResumeSweepUpsertsPositionsAndRefetchesItemsThatLeftTheSet() async throws {
        // Saved well before the cursor, so the delta's overlap window never
        // re-delivers them: the sweep has to be the thing that does the work.
        let saved = source.serverClock.addingTimeInterval(-3600)
        for n in 1...3 { source.add(Fixture.movie(n), savedAt: saved) }
        await engine.syncIfNeeded(libraries: [library])

        // Locally m1 is in progress. On the server it has since been finished
        // (played, position 0) and m2 has been started.
        try await repo.upsertUserData([("m1", UserData(playbackPosition: 600))], scope: scope)
        source.setUserData("m1", UserData(playbackPosition: 0, isPlayed: true))
        source.resumeSet = [CatalogUserDataRow(itemId: "m2", userData: UserData(playbackPosition: 1200))]
        // Move the server clock past the delta overlap. A user-data write does not
        // bump DateLastSaved on a real server, so the catalogue delta must return
        // nothing here and the resume sweep has to do the work itself.
        source.serverClock = source.serverClock.addingTimeInterval(3600)

        await engine.syncIfNeeded(libraries: [library])

        let m1 = try await repo.item(id: "m1", scope: scope)?.userData
        let m2 = try await repo.item(id: "m2", scope: scope)?.userData
        XCTAssertEqual(m1?.isPlayed, true, "left the resume set → refetched → finished")
        XCTAssertEqual(m1?.playbackPosition, 0)
        XCTAssertEqual(m2?.playbackPosition, 1200)
        XCTAssertTrue(source.entryRequests.contains(["m1"]), "exactly the item that left was refetched")
    }

    func testFavouritesSweepSetsAndClears() async throws {
        for n in 1...3 { source.add(Fixture.movie(n, favorite: n == 1)) }
        await engine.syncIfNeeded(libraries: [library])   // m1 favourite locally

        source.favorites = ["m2"]                           // elsewhere: unfav m1, fav m2
        await engine.syncIfNeeded(libraries: [library])

        let favs = try await repo.favoriteIds(scope: scope)
        XCTAssertEqual(favs, ["m2"])
    }

    func testFavouritesSweepDoesNotClearAPendingLocalFavourite() async throws {
        for n in 1...2 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])
        // User favourited m1 offline: local true + outbox row. Server still says no.
        try await db.dbWriter.write { d in
            try d.execute(sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE itemId = 'm1'")
            try d.execute(sql: """
                INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                VALUES ('o1','srv','usr','m1','favorite','true', CURRENT_TIMESTAMP, 0)
                """)
        }
        source.favorites = []
        await engine.syncIfNeeded(libraries: [library])
        let favs = try await repo.favoriteIds(scope: scope)
        XCTAssertEqual(favs, ["m1"], "pending write is the truth until acknowledged")
    }

    func testRecentlyPlayedSweepMarksWatched() async throws {
        for n in 1...2 { source.add(Fixture.movie(n)) }
        await engine.syncIfNeeded(libraries: [library])
        source.recentlyPlayed = [CatalogUserDataRow(itemId: "m2", userData: UserData(playCount: 1, isPlayed: true, lastPlayedDate: Date()))]
        await engine.syncIfNeeded(libraries: [library])
        let m2 = try await repo.item(id: "m2", scope: scope)?.userData
        XCTAssertEqual(m2?.isPlayed, true)
    }

    func testFullSweepCatchesAnUnwatchNobodyElseReports() async throws {
        let saved = source.serverClock.addingTimeInterval(-3600)
        for n in 1...2 { source.add(Fixture.movie(n, played: true), savedAt: saved) }
        await engine.syncIfNeeded(libraries: [library])
        source.setUserData("m1", UserData(isPlayed: false))     // un-watched elsewhere; no hot sweep sees it
        source.serverClock = source.serverClock.addingTimeInterval(3600)   // past the delta overlap
        await engine.syncIfNeeded(libraries: [library])
        var m1 = try await repo.item(id: "m1", scope: scope)?.userData
        XCTAssertEqual(m1?.isPlayed, true, "hot sweeps cannot see an un-watch")
        await engine.reconcileAll(libraries: [library])          // daily path
        m1 = try await repo.item(id: "m1", scope: scope)?.userData
        XCTAssertEqual(m1?.isPlayed, false, "full sweep does")
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
        XCTAssertEqual(CatalogSyncEngine.itemTypes(for: nil), ["Movie", "Series", "Season", "Episode"], "mixed libraries sync everything the video screens show")
        XCTAssertNil(CatalogSyncEngine.itemTypes(for: .music))
        XCTAssertNil(CatalogSyncEngine.itemTypes(for: .playlists))
    }

    // MARK: Libraries, detail, collections — the engine is the only door to the server

    func testRefreshLibrariesKeepsCatalogueShapesAndDropsVanished() async throws {
        source.libraryList = [
            MediaLibrary(id: ItemID("mov"), name: "Movies", collectionType: .movies),
            MediaLibrary(id: ItemID("mus"), name: "Music", collectionType: .music),
            MediaLibrary(id: ItemID("mix"), name: "Mixed", collectionType: nil),
        ]
        let kept = try await engine.refreshLibraries()
        XCTAssertEqual(kept.map(\.name), ["Movies", "Mixed"], "music has no catalogue shape")
        let saved = try await repo.libraries(scope: scope)
        XCTAssertEqual(saved.map(\.id.rawValue), ["mov", "mix"])

        // Movies vanishes from the server; its rows go with it.
        try await repo.upsert([Fixture.movie(1)].map { e in var c = e; c.libraryId = "mov"; return c }, scope: scope)
        source.libraryList.removeFirst()
        _ = try await engine.refreshLibraries()
        let after = try await repo.libraries(scope: scope)
        XCTAssertEqual(after.map(\.id.rawValue), ["mix"])
        let rows = try await repo.count(libraryId: "mov", scope: scope)
        XCTAssertEqual(rows, 0)
    }

    func testRefreshLibrariesFailureLeavesSavedListAlone() async throws {
        try await repo.saveLibraries([MediaLibrary(id: ItemID("mov"), name: "Movies", collectionType: .movies)], scope: scope)
        let failing = FailingSource()
        let engine = CatalogSyncEngine(source: failing, repository: repo, scope: scope)
        do {
            _ = try await engine.refreshLibraries()
            XCTFail("expected a throw")
        } catch {}
        let saved = try await repo.libraries(scope: scope)
        XCTAssertEqual(saved.count, 1, "an unreachable server is not 'no libraries'")
    }

    func testFetchDetailCachesAndOverlaysCatalogueUserData() async throws {
        source.add(Fixture.movie(1))
        await engine.syncIfNeeded(libraries: [library])
        // The user favourited it offline: an outbox row is pending, the catalogue
        // already says favourite. The server's JSON still says it is not.
        try await db.dbWriter.write { d in
            try d.execute(sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE itemId = 'm1'")
            try d.execute(sql: """
                INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                VALUES ('o1','srv','usr','m1','favorite','true', CURRENT_TIMESTAMP, 0)
                """)
        }
        var full = MediaItem(id: ItemID("m1"), title: "Movie 1", overview: "Long", mediaType: .movie)
        full.userData = UserData(isFavorite: false)
        source.details["m1"] = full

        let item = try await engine.fetchDetail(itemId: "m1")
        XCTAssertEqual(item.overview, "Long")
        XCTAssertEqual(item.userData?.isFavorite, true, "the pending edit wins over the fetched JSON")
        let cached = try await repo.cachedDetail(id: "m1", scope: scope)
        XCTAssertEqual(cached?.item.overview, "Long")
        XCTAssertEqual(cached?.isStale, false)
        XCTAssertEqual(source.detailRequests, ["m1"])
    }

    func testDeltaMarksCachedDetailStaleWhenServerEditsTheItem() async throws {
        source.add(Fixture.movie(1), savedAt: source.serverClock.addingTimeInterval(-3600))
        await engine.syncIfNeeded(libraries: [library])
        source.details["m1"] = MediaItem(id: ItemID("m1"), title: "Movie 1", overview: "v1", mediaType: .movie)
        _ = try await engine.fetchDetail(itemId: "m1")
        // Let the clock move so syncedAt lands after the detail's updatedAt.
        try await Task.sleep(for: .milliseconds(20))

        // Another client renames the movie; the delta re-delivers it.
        source.add(Fixture.movie(1, name: "Movie 1 (Director's Cut)"), savedAt: source.serverClock.addingTimeInterval(60))
        source.serverClock = source.serverClock.addingTimeInterval(120)
        await engine.syncIfNeeded(libraries: [library])

        let cached = try await repo.cachedDetail(id: "m1", scope: scope)
        XCTAssertEqual(cached?.isStale, true, "the row was re-synced after the detail was fetched")
        XCTAssertEqual(cached?.item.overview, "v1", "the stale copy still renders while the refresh runs")
    }

    func testCollectionMembershipSyncsOnBootstrapAndRefreshesOnReconcile() async throws {
        let collections = CatalogSyncEngine.Library(id: Fixture.collections, name: "Collections", itemTypes: ["BoxSet"])
        for n in 1...3 { source.add(Fixture.movie(n)) }
        source.add(Fixture.boxSet(1))
        source.collectionMembers["b1"] = ["m2", "m1", "zz-not-synced"]

        await engine.syncIfNeeded(libraries: [library, collections])

        let members = try await repo.collectionItems(collectionId: "b1", scope: scope)
        XCTAssertEqual(members.map(\.id.rawValue), ["m2", "m1"], "server order, unknown ids joined away")
        XCTAssertEqual(source.collectionRequests, ["b1"], "bootstrap's closing reconcile asks once")

        // Membership changes without the BoxSet itself changing; reconcile catches it.
        source.collectionMembers["b1"] = ["m3"]
        await engine.reconcileAll(libraries: [library, collections])
        let after = try await repo.collectionItems(collectionId: "b1", scope: scope)
        XCTAssertEqual(after.map(\.id.rawValue), ["m3"])
    }

    func testDeltaRefreshesOnlyTheCollectionsTheServerChanged() async throws {
        let collections = CatalogSyncEngine.Library(id: Fixture.collections, name: "Collections", itemTypes: ["BoxSet"])
        source.add(Fixture.boxSet(1), savedAt: source.serverClock.addingTimeInterval(-3600))
        source.add(Fixture.boxSet(2), savedAt: source.serverClock.addingTimeInterval(-3600))
        await engine.syncIfNeeded(libraries: [collections])
        source.collectionRequests = []

        source.add(Fixture.boxSet(2, name: "Set 2 renamed"), savedAt: source.serverClock.addingTimeInterval(60))
        source.serverClock = source.serverClock.addingTimeInterval(120)
        await engine.syncIfNeeded(libraries: [collections])
        XCTAssertEqual(source.collectionRequests, ["b2"])
    }
}

/// Every call fails as if the server were down.
private final class FailingSource: CatalogSyncSource, @unchecked Sendable {
    private var error: any Error { AppError.serverUnreachable(url: URL(string: "https://down")!) }
    func libraries() async throws -> [MediaLibrary] { throw error }
    func catalogDetail(id: String) async throws -> MediaItem { throw error }
    func collectionMemberIds(collectionId: String) async throws -> [String] { throw error }
    func catalogPage(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws -> CatalogPage { throw error }
    func catalogChanges(libraryId: String, itemTypes: [String], since: Date, startIndex: Int, limit: Int) async throws -> CatalogPage { throw error }
    func catalogIds(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws -> CatalogIdPage { throw error }
    func catalogEntries(ids: [String], libraryId: String) async throws -> [CatalogEntry] { throw error }
    func resumeUserData() async throws -> [CatalogUserDataRow] { throw error }
    func favoriteIds() async throws -> Set<String> { throw error }
    func recentlyPlayedUserData(limit: Int) async throws -> [CatalogUserDataRow] { throw error }
    func userDataPage(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws -> (rows: [CatalogUserDataRow], totalCount: Int) { throw error }
}
