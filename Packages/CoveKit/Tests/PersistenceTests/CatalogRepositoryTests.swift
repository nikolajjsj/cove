import Foundation
import GRDB
import Models
import XCTest

@testable import Persistence

final class CatalogRepositoryTests: XCTestCase {
    var db: DatabaseManager!
    var repo: CatalogRepository!
    let scope = CatalogRepository.Scope(serverId: "srv", userId: "usr")
    let lib = "lib"
    let byName = SortOptions(field: .name, order: .ascending)

    override func setUp() async throws {
        db = try DatabaseManager()
        try await db.dbWriter.write { d in
            try d.execute(sql: "INSERT INTO servers (id, name, url, userId, serverType) VALUES ('srv','S','https://s','usr','jellyfin')")
        }
        repo = CatalogRepository(database: db)
    }

    private func entry(_ id: String, name: String, sort: String? = nil, year: Int? = nil, created: TimeInterval = 0,
                       genres: [String] = [], studios: [String] = [], rating: Double? = nil,
                       favorite: Bool = false, played: Bool = false) -> CatalogEntry {
        CatalogEntry(
            id: id, libraryId: lib, type: "Movie", mediaType: .movie, name: name, sortName: sort ?? name,
            productionYear: year, dateCreated: Date(timeIntervalSince1970: 1_600_000_000 + created),
            communityRating: rating,
            imageTags: [.primary: "tag-\(id)"],
            genres: genres.map { CatalogGenre(id: $0.lowercased(), name: $0) }, studios: studios,
            userData: UserData(isFavorite: favorite, isPlayed: played))
    }

    private func ids(sort: SortOptions? = nil, filter: FilterOptions? = nil) async throws -> [String] {
        try await repo.pagedItems(
            libraryId: lib, itemTypes: ["Movie"], sort: sort ?? byName,
            filter: filter ?? FilterOptions(limit: 50, startIndex: 0), scope: scope
        ).items.map(\.id.rawValue)
    }

    func testUpsertIsIdempotentAndUpdatesInPlace() async throws {
        try await repo.upsert([entry("a", name: "Alpha")], scope: scope)
        try await repo.upsert([entry("a", name: "Alpha Renamed")], scope: scope)
        let count = try await repo.count(libraryId: lib, scope: scope)
        let title = try await repo.item(id: "a", scope: scope)?.title
        XCTAssertEqual(count, 1)
        XCTAssertEqual(title, "Alpha Renamed")
    }

    func testUpsertPreservesReconcileStamp() async throws {
        try await repo.upsert([entry("a", name: "A")], scope: scope)
        let stamp = Date(timeIntervalSince1970: 1_650_000_000)
        try await repo.markSeen(itemIds: ["a"], at: stamp, scope: scope)
        try await repo.upsert([entry("a", name: "A2")], scope: scope)
        let seen = try await db.dbWriter.read { d in
            try Date.fetchOne(d, sql: "SELECT lastSeenInReconcile FROM catalog_items WHERE itemId = 'a'")
        }
        XCTAssertEqual(seen, stamp, "a page upsert must not clear the reconcile stamp")
    }

    func testSortsMatchSortField() async throws {
        try await repo.upsert([
            entry("b", name: "Beta", year: 2001, created: 20, rating: 7),
            entry("a", name: "alpha", year: 1999, created: 10, rating: 9),
            entry("c", name: "Gamma", year: 2010, created: 30, rating: 5),
        ], scope: scope)
        let byNameAsc = try await ids(sort: SortOptions(field: .name, order: .ascending))
        let byAddedDesc = try await ids(sort: SortOptions(field: .dateAdded, order: .descending))
        let byRatingDesc = try await ids(sort: SortOptions(field: .communityRating, order: .descending))
        XCTAssertEqual(byNameAsc, ["a", "b", "c"], "NOCASE")
        XCTAssertEqual(byAddedDesc, ["c", "b", "a"])
        XCTAssertEqual(byRatingDesc, ["a", "b", "c"])
    }

    func testFiltersMatchFilterOptions() async throws {
        try await repo.upsert([
            entry("a", name: "A", year: 1994, genres: ["Drama"], studios: ["Warner"], rating: 8.5, favorite: true, played: true),
            entry("b", name: "B", year: 2003, genres: ["Comedy"], rating: 6.0),
            entry("c", name: "C", year: 1999, genres: ["Drama", "Comedy"], rating: 7.9, played: true),
        ], scope: scope)
        let genre = try await ids(filter: FilterOptions(genres: ["Drama"], limit: 50, startIndex: 0))
        let years = try await ids(filter: FilterOptions(years: [1990, 1994, 1999], limit: 50, startIndex: 0))
        let fav = try await ids(filter: FilterOptions(isFavorite: true, limit: 50, startIndex: 0))
        let unplayed = try await ids(filter: FilterOptions(isPlayed: false, limit: 50, startIndex: 0))
        let rated = try await ids(filter: FilterOptions(limit: 50, startIndex: 0, minCommunityRating: 7.0))
        let studio = try await ids(filter: FilterOptions(limit: 50, startIndex: 0, studios: ["Warner"]))
        XCTAssertEqual(genre, ["a", "c"])
        XCTAssertEqual(years, ["a", "c"])
        XCTAssertEqual(fav, ["a"])
        XCTAssertEqual(unplayed, ["b"])
        XCTAssertEqual(rated, ["a", "c"])
        XCTAssertEqual(studio, ["a"])
    }

    func testPagingIsStableOverTies() async throws {
        try await repo.upsert((1...10).map { entry("i\($0)", name: "Same", sort: "Same") }, scope: scope)
        let first = try await ids(filter: FilterOptions(limit: 4, startIndex: 0))
        let second = try await ids(filter: FilterOptions(limit: 4, startIndex: 4))
        let third = try await ids(filter: FilterOptions(limit: 4, startIndex: 8))
        XCTAssertEqual(Set(first + second + third).count, 10, "no row repeated or skipped across pages")
    }

    func testFullTextSearchFoldsDiacriticsAndPrefixes() async throws {
        try await repo.upsert([
            entry("a", name: "Amélie"), entry("b", name: "The Godfather"), entry("c", name: "Godzilla"),
        ], scope: scope)
        let amelie = try await ids(filter: FilterOptions(limit: 50, startIndex: 0, searchTerm: "amelie"))
        let god = try await ids(filter: FilterOptions(limit: 50, startIndex: 0, searchTerm: "god"))
        XCTAssertEqual(amelie, ["a"])
        XCTAssertEqual(god, ["c", "b"])
    }

    func testGenresListedPerLibrary() async throws {
        try await repo.upsert([entry("a", name: "A", genres: ["Drama", "Action"]), entry("b", name: "B", genres: ["drama"])], scope: scope)
        let g = try await repo.genres(libraryId: lib, scope: scope)
        XCTAssertEqual(g.map { $0.lowercased() }.sorted(), ["action", "drama", "drama"].sorted())
    }

    func testDeleteCascadesToUserDataGenresAndSearch() async throws {
        try await repo.upsert([entry("a", name: "Zebra", genres: ["Drama"], favorite: true)], scope: scope)
        try await repo.delete(itemIds: ["a"], scope: scope)
        let counts = try await db.dbWriter.read { d -> [Int] in
            try ["catalog_items", "catalog_user_data", "catalog_item_genres"].map {
                try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM \($0)") ?? -1
            }
        }
        let search = try await ids(filter: FilterOptions(limit: 50, startIndex: 0, searchTerm: "zebra"))
        XCTAssertEqual(counts, [0, 0, 0])
        XCTAssertEqual(search, [])
    }

    func testPendingOutboxFieldIsNotOverwrittenBySync() async throws {
        try await repo.upsert([entry("a", name: "A", favorite: false)], scope: scope)
        try await db.dbWriter.write { d in
            try d.execute(sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE itemId = 'a'")
            try d.execute(sql: """
                INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                VALUES ('o1','srv','usr','a','favorite','true', CURRENT_TIMESTAMP, 0)
                """)
        }
        try await repo.upsert([entry("a", name: "A", favorite: false, played: true)], scope: scope)
        let item = try await repo.item(id: "a", scope: scope)
        XCTAssertEqual(item?.userData?.isFavorite, true, "pending field is the truth until acknowledged")
        XCTAssertEqual(item?.userData?.isPlayed, true, "other fields still take the server's value")
    }

    func testLeanItemCarriesImageTagsAndGenres() async throws {
        try await repo.upsert([entry("a", name: "A", genres: ["Drama"])], scope: scope)
        let item = try await repo.item(id: "a", scope: scope)
        XCTAssertEqual(item?.imageTags?[.primary], "tag-a")
        XCTAssertEqual(item?.genres, ["Drama"])
        XCTAssertNil(item?.overview, "detail tier is not in the catalogue")
    }

    // MARK: Libraries

    func testLibrariesRoundTripInOrder() async throws {
        let libs = [
            MediaLibrary(id: ItemID("b"), name: "TV", collectionType: .tvshows),
            MediaLibrary(id: ItemID("a"), name: "Films", collectionType: .movies),
        ]
        try await repo.saveLibraries(libs, scope: scope)
        let back = try await repo.libraries(scope: scope)
        XCTAssertEqual(back, libs, "order preserved, types preserved")
        try await repo.saveLibraries([libs[1]], scope: scope)
        let again = try await repo.libraries(scope: scope)
        XCTAssertEqual(again.map(\.name), ["Films"], "save replaces, never accumulates")
    }

    // MARK: Derived feeds

    private func episode(_ id: String, series: String, season: Int, ep: Int, played: Bool, position: TimeInterval = 0, lastPlayed: Date? = nil) -> CatalogEntry {
        CatalogEntry(
            id: id, libraryId: lib, seriesId: series, type: "Episode", mediaType: .episode,
            name: id, sortName: id, dateCreated: Date(timeIntervalSince1970: 1_600_000_000),
            indexNumber: ep, parentIndexNumber: season, seriesName: series,
            userData: UserData(playbackPosition: position, isPlayed: played, lastPlayedDate: lastPlayed))
    }

    func testResumeFeedIsInProgressUnplayedByRecency() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try await repo.upsert([
            entry("done", name: "Done", played: true),
            episode("e-old", series: "S", season: 1, ep: 1, played: false, position: 300, lastPlayed: t0),
            episode("e-new", series: "S", season: 1, ep: 2, played: false, position: 60, lastPlayed: t0.addingTimeInterval(100)),
            entry("zero", name: "Zero"),
        ], scope: scope)
        let ids = try await repo.resumeItems(scope: scope).map(\.id.rawValue)
        XCTAssertEqual(ids, ["e-new", "e-old"])
    }

    func testNextUpPicksFirstUnplayedAfterLatestPlayedAndSkipsSpecials() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await repo.upsert([
            episode("s0e1", series: "A", season: 0, ep: 1, played: false),           // special: ignored
            episode("s1e1", series: "A", season: 1, ep: 1, played: true, lastPlayed: t),
            episode("s1e2", series: "A", season: 1, ep: 2, played: true, lastPlayed: t.addingTimeInterval(10)),
            episode("s1e3", series: "A", season: 1, ep: 3, played: false),
            episode("s1e4", series: "A", season: 1, ep: 4, played: false),
            episode("b1e1", series: "B", season: 1, ep: 1, played: false),           // never started: no NextUp
        ], scope: scope)
        let ids = try await repo.nextUp(scope: scope).map(\.id.rawValue)
        XCTAssertEqual(ids, ["s1e3"])
    }

    func testScopeWideSearchSpansLibrariesAndAppliesFilters() async throws {
        var other = entry("x", name: "Godzilla Minus One", year: 2023, rating: 8.0)
        other.libraryId = "other-lib"
        try await repo.upsert([entry("g", name: "Godzilla", year: 1954, rating: 7.5), other], scope: scope)
        let all = try await repo.search(term: "godz", filter: FilterOptions(limit: 10, startIndex: 0), scope: scope).map(\.id.rawValue)
        let recent = try await repo.search(term: "godz", filter: FilterOptions(years: [2023], limit: 10, startIndex: 0), scope: scope).map(\.id.rawValue)
        XCTAssertEqual(Set(all), ["g", "x"])
        XCTAssertEqual(recent, ["x"])
    }

    func testReplaceFavoritesProtectsPendingOutbox() async throws {
        try await repo.upsert([entry("a", name: "A", favorite: true), entry("b", name: "B")], scope: scope)
        try await db.dbWriter.write { d in
            try d.execute(sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE itemId = 'b'")
            try d.execute(sql: """
                INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                VALUES ('o1','srv','usr','b','favorite','true', CURRENT_TIMESTAMP, 0)
                """)
        }
        try await repo.replaceFavorites(with: [], scope: scope)   // server: nothing is a favourite
        let favs = try await repo.favoriteIds(scope: scope)
        XCTAssertEqual(favs, ["b"], "a cleared, b protected")
    }

    // MARK: Detail tier

    private func fullItem(_ id: String, overview: String) -> MediaItem {
        MediaItem(id: ItemID(id), title: id, overview: overview, mediaType: .movie,
                  people: [], userData: UserData(isFavorite: false, isPlayed: false))
    }

    func testDetailRoundTripsAndOverlaysCatalogUserData() async throws {
        try await repo.upsert([entry("a", name: "A")], scope: scope)
        try await repo.saveDetail(fullItem("a", overview: "Long text"), scope: scope)   // JSON: not a favourite
        // A later sweep learns it is a favourite. The cached JSON is now stale.
        try await repo.upsertUserData([("a", UserData(isFavorite: true))], scope: scope)
        let d = try await repo.detail(id: "a", scope: scope)
        XCTAssertEqual(d?.overview, "Long text")
        XCTAssertEqual(d?.userData?.isFavorite, true, "user data comes from catalog_user_data, not the JSON")
    }

    func testSaveDetailRefreshesUserDataButRespectsPendingOutbox() async throws {
        try await repo.upsert([entry("a", name: "A")], scope: scope)
        try await db.dbWriter.write { d in
            try d.execute(sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE itemId = 'a'")
            try d.execute(sql: """
                INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                VALUES ('o1','srv','usr','a','favorite','true', CURRENT_TIMESTAMP, 0)
                """)
        }
        var fresh = fullItem("a", overview: "x")
        fresh.userData = UserData(isFavorite: false, isPlayed: true)   // server: not favourite, but played
        try await repo.saveDetail(fresh, scope: scope)
        let ud = try await repo.userData(itemId: "a", scope: scope)
        XCTAssertEqual(ud?.isFavorite, true, "pending favourite survives")
        XCTAssertEqual(ud?.isPlayed, true, "unprotected field takes the server's value")
    }

    func testDetailMissingIsNil() async throws {
        let d = try await repo.detail(id: "nope", scope: scope)
        XCTAssertNil(d)
        let c = try await repo.cachedDetail(id: "nope", scope: scope)
        XCTAssertNil(c)
    }

    func testCachedDetailIsStaleOnlyAfterTheRowIsResynced() async throws {
        try await repo.upsert([entry("a", name: "A")], scope: scope)
        try await repo.saveDetail(fullItem("a", overview: "x"), scope: scope)
        let fresh = try await repo.cachedDetail(id: "a", scope: scope)
        XCTAssertEqual(fresh?.isStale, false)
        // A user-data sweep does not touch the catalogue row: still fresh.
        try await repo.upsertUserData([("a", UserData(isPlayed: true))], scope: scope)
        let afterSweep = try await repo.cachedDetail(id: "a", scope: scope)
        XCTAssertEqual(afterSweep?.isStale, false)
        // A catalogue upsert does.
        try await Task.sleep(for: .milliseconds(20))
        try await repo.upsert([entry("a", name: "A renamed")], scope: scope)
        let afterSync = try await repo.cachedDetail(id: "a", scope: scope)
        XCTAssertEqual(afterSync?.isStale, true)
        // Saving a new detail clears it.
        try await repo.saveDetail(fullItem("a", overview: "y"), scope: scope)
        let refetched = try await repo.cachedDetail(id: "a", scope: scope)
        XCTAssertEqual(refetched?.isStale, false)
    }

    // MARK: Collections

    func testCollectionMembersKeepServerOrderAndCascadeWithTheBoxSet() async throws {
        try await repo.upsert([entry("a", name: "A"), entry("b", name: "B")], scope: scope)
        let set = CatalogEntry(id: "s1", libraryId: "sets", type: "BoxSet", mediaType: .collection,
                               name: "Set", sortName: "Set", dateCreated: Date(timeIntervalSince1970: 1_600_000_000))
        try await repo.upsert([set], scope: scope)
        try await repo.replaceCollectionMembers(collectionId: "s1", itemIds: ["b", "ghost", "a"], scope: scope)
        let members = try await repo.collectionItems(collectionId: "s1", scope: scope)
        XCTAssertEqual(members.map(\.id.rawValue), ["b", "a"])
        let ids = try await repo.collectionIds(libraryId: "sets", scope: scope)
        XCTAssertEqual(ids, ["s1"])

        try await repo.replaceCollectionMembers(collectionId: "s1", itemIds: ["a"], scope: scope)
        let replaced = try await repo.collectionItems(collectionId: "s1", scope: scope)
        XCTAssertEqual(replaced.map(\.id.rawValue), ["a"], "replace, not merge")

        try await repo.delete(itemIds: ["s1"], scope: scope)
        let rows = try await db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM catalog_collection_items WHERE collectionId = 's1'") ?? -1
        }
        XCTAssertEqual(rows, 0, "membership goes with the BoxSet")
    }

    func testEvictionIsLRUAndSparesPinnedAndDownloaded() async throws {
        for id in ["old", "mid", "new", "pinned", "downloaded"] {
            try await repo.saveDetail(fullItem(id, overview: String(repeating: "x", count: 1000)), pinned: id == "pinned", scope: scope)
        }
        // Order the access times explicitly.
        try await db.dbWriter.write { d in
            for (i, id) in ["old", "mid", "new", "pinned", "downloaded"].enumerated() {
                try d.execute(sql: "UPDATE catalog_item_details SET lastAccessedAt = ? WHERE itemId = ?",
                              arguments: [Date(timeIntervalSince1970: 1_700_000_000 + Double(i)), id])
            }
            // A live download for 'downloaded' — no explicit pin.
            try d.execute(sql: """
                INSERT INTO downloads (id, itemId, serverId, title, mediaType, state, remoteURL)
                VALUES ('dl1', 'downloaded', 'srv', 'D', 'movie', 'completed', 'https://s/x')
                """)
        }
        // Budget fits exactly one unprotected row, whatever the encoder makes of it.
        let rowBytes = try await db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT LENGTH(json) FROM catalog_item_details WHERE itemId = 'new'") ?? 0
        }
        let removed = try await repo.evictDetails(budgetBytes: rowBytes + rowBytes / 2, scope: scope)
        let remaining = try await db.dbWriter.read { d in
            try String.fetchAll(d, sql: "SELECT itemId FROM catalog_item_details ORDER BY itemId")
        }
        XCTAssertEqual(removed, 2, "old and mid go; new fits the budget")
        XCTAssertEqual(remaining, ["downloaded", "new", "pinned"])
    }

    func testSaveDetailNeverUnpins() async throws {
        try await repo.saveDetail(fullItem("a", overview: "1"), pinned: true, scope: scope)
        try await repo.saveDetail(fullItem("a", overview: "2"), pinned: false, scope: scope)
        let pinned = try await db.dbWriter.read { d in
            try Bool.fetchOne(d, sql: "SELECT pinned FROM catalog_item_details WHERE itemId = 'a'")
        }
        XCTAssertEqual(pinned, true)
    }

    func testMissingIdsFindsOrphans() async throws {
        try await repo.upsert([entry("a", name: "A")], scope: scope)
        let missing = try await repo.missingIds(among: ["a", "gone", "also-gone"], scope: scope)
        XCTAssertEqual(missing, ["gone", "also-gone"])
    }

    // MARK: Seasons & episodes from the catalogue

    func testSeasonsAndEpisodesComeFromCatalogueRows() async throws {
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        try await repo.upsert([
            CatalogEntry(id: "s1", libraryId: lib, seriesId: "show", type: "Season", mediaType: .season, name: "Season 1", sortName: "1", dateCreated: created, indexNumber: 1),
            CatalogEntry(id: "s2", libraryId: lib, seriesId: "show", type: "Season", mediaType: .season, name: "Season 2", sortName: "2", dateCreated: created, indexNumber: 2),
            CatalogEntry(id: "e2", libraryId: lib, seriesId: "show", seasonId: "s1", type: "Episode", mediaType: .episode, name: "Two", sortName: "2", dateCreated: created, runTimeTicks: 600_0000000, indexNumber: 2, parentIndexNumber: 1, userData: UserData(isPlayed: true)),
            CatalogEntry(id: "e1", libraryId: lib, seriesId: "show", seasonId: "s1", type: "Episode", mediaType: .episode, name: "One", sortName: "1", dateCreated: created, indexNumber: 1, parentIndexNumber: 1),
        ], scope: scope)
        try await repo.saveDetail(MediaItem(id: ItemID("e1"), title: "One", overview: "Pilot.", mediaType: .episode), scope: scope)

        let seasons = try await repo.seasons(seriesId: "show", scope: scope)
        let eps = try await repo.episodes(seasonId: "s1", scope: scope)
        XCTAssertEqual(seasons.map(\.seasonNumber), [1, 2])
        XCTAssertEqual(seasons.first?.episodeCount, 2)
        XCTAssertEqual(eps.map(\.episodeNumber), [1, 2])
        XCTAssertEqual(eps.first?.overview, "Pilot.", "overview joins in from the detail cache")
        XCTAssertNil(eps.last?.overview)
        XCTAssertEqual(eps.last?.userData?.isPlayed, true)
        XCTAssertEqual(eps.last?.runtime, 600)
    }

    func testNextEpisodeCrossesSeasonsAndSkipsSpecials() async throws {
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        try await repo.upsert([
            episode("s0e1", series: "A", season: 0, ep: 1, played: false),
            episode("s1e1", series: "A", season: 1, ep: 1, played: true),
            episode("s1e2", series: "A", season: 1, ep: 2, played: false),
            episode("s2e1", series: "A", season: 2, ep: 1, played: false),
            CatalogEntry(id: "other", libraryId: lib, seriesId: "B", type: "Episode", mediaType: .episode, name: "b", sortName: "b", dateCreated: created, indexNumber: 1, parentIndexNumber: 1),
        ], scope: scope)
        let n1 = try await repo.nextEpisode(after: "s1e1", scope: scope)?.id.rawValue
        let n2 = try await repo.nextEpisode(after: "s1e2", scope: scope)?.id.rawValue
        let n3 = try await repo.nextEpisode(after: "s2e1", scope: scope)
        XCTAssertEqual(n1, "s1e2")
        XCTAssertEqual(n2, "s2e1", "crosses into the next season")
        XCTAssertNil(n3, "last episode has no next")
    }

    func testStudiosListedPerLibrary() async throws {
        try await repo.upsert([entry("a", name: "A", studios: ["Warner", "A24"]), entry("b", name: "B", studios: ["a24"])], scope: scope)
        let s = try await repo.studios(libraryId: lib, scope: scope)
        XCTAssertEqual(s.map { $0.lowercased() }.sorted(), ["a24", "a24", "warner"])
    }
}
