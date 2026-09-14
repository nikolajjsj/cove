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
}
