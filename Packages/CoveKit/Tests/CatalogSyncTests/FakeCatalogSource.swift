import Foundation
import MediaServerKit
import Models

/// A server in a box. Items live in a dictionary; the clock is whatever the test
/// says it is; pages can be made to fail on demand.
///
/// `@unchecked Sendable` because tests mutate it from one task at a time.
final class FakeCatalogSource: CatalogSyncSource, @unchecked Sendable {
    struct ServerItem {
        var entry: CatalogEntry
        /// The server's idea of when it last saved this item.
        var lastSaved: Date
    }

    var items: [String: ServerItem] = [:]
    /// What the `Date` header says. Deliberately independent of `Date()`.
    var serverClock = Date(timeIntervalSince1970: 1_700_000_000)
    /// Throw on the Nth catalogChanges page (0-based). Cleared after firing.
    var failChangesOnPage: Int?
    var pageRequests = 0
    var changeRequests = 0
    var idRequests = 0
    var entryRequests: [[String]] = []

    /// User-data sweep state. Tests set these directly to model other clients.
    var resumeSet: [CatalogUserDataRow] = []
    var favorites: Set<String> = []
    var recentlyPlayed: [CatalogUserDataRow] = []

    func add(_ entry: CatalogEntry, savedAt: Date? = nil) {
        items[entry.id] = ServerItem(entry: entry, lastSaved: savedAt ?? serverClock)
    }

    func remove(_ id: String) { items[id] = nil }

    private func ordered(_ libraryId: String, _ types: [String]) -> [ServerItem] {
        items.values
            .filter { $0.entry.libraryId == libraryId && types.contains($0.entry.type) }
            .sorted { a, b in
                a.entry.dateCreated != b.entry.dateCreated
                    ? a.entry.dateCreated < b.entry.dateCreated : a.entry.id < b.entry.id
            }
    }

    func catalogPage(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws -> CatalogPage {
        pageRequests += 1
        let all = ordered(libraryId, itemTypes)
        let slice = all.dropFirst(startIndex).prefix(limit)
        return CatalogPage(entries: slice.map(\.entry), totalCount: all.count, serverDate: serverClock)
    }

    func catalogChanges(libraryId: String, itemTypes: [String], since: Date, startIndex: Int, limit: Int) async throws -> CatalogPage {
        let page = startIndex / max(limit, 1)
        changeRequests += 1
        if let f = failChangesOnPage, f == page {
            failChangesOnPage = nil
            throw AppError.serverUnreachable(url: URL(string: "https://fake")!)
        }
        let all = ordered(libraryId, itemTypes).filter { $0.lastSaved >= since }
        let slice = all.dropFirst(startIndex).prefix(limit)
        return CatalogPage(entries: slice.map(\.entry), totalCount: all.count, serverDate: serverClock)
    }

    func catalogIds(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws -> CatalogIdPage {
        idRequests += 1
        let all = ordered(libraryId, itemTypes)
        let slice = all.dropFirst(startIndex).prefix(limit)
        return CatalogIdPage(ids: slice.map(\.entry.id), totalCount: all.count, serverDate: serverClock)
    }

    func catalogEntries(ids: [String], libraryId: String) async throws -> [CatalogEntry] {
        entryRequests.append(ids)
        return ids.compactMap { items[$0]?.entry }
    }

    // MARK: sweeps

    func resumeUserData() async throws -> [CatalogUserDataRow] { resumeSet }
    func favoriteIds() async throws -> Set<String> { favorites }
    func recentlyPlayedUserData(limit: Int) async throws -> [CatalogUserDataRow] {
        Array(recentlyPlayed.prefix(limit))
    }
    func userDataPage(libraryId: String, itemTypes: [String], startIndex: Int, limit: Int) async throws
        -> (rows: [CatalogUserDataRow], totalCount: Int)
    {
        let all = ordered(libraryId, itemTypes).compactMap { si -> CatalogUserDataRow? in
            si.entry.userData.map { CatalogUserDataRow(itemId: si.entry.id, userData: $0) }
        }
        return (Array(all.dropFirst(startIndex).prefix(limit)), all.count)
    }

    /// Change an item's server-side user data in place (what another client did).
    func setUserData(_ id: String, _ ud: UserData) {
        guard var si = items[id] else { return }
        si.entry = CatalogEntry(
            id: si.entry.id, libraryId: si.entry.libraryId, parentId: si.entry.parentId,
            seriesId: si.entry.seriesId, seasonId: si.entry.seasonId, type: si.entry.type,
            mediaType: si.entry.mediaType, name: si.entry.name, sortName: si.entry.sortName,
            productionYear: si.entry.productionYear, premiereDate: si.entry.premiereDate,
            dateCreated: si.entry.dateCreated, runTimeTicks: si.entry.runTimeTicks,
            communityRating: si.entry.communityRating, criticRating: si.entry.criticRating,
            officialRating: si.entry.officialRating, indexNumber: si.entry.indexNumber,
            parentIndexNumber: si.entry.parentIndexNumber, seriesName: si.entry.seriesName,
            imageTags: si.entry.imageTags, genres: si.entry.genres, studios: si.entry.studios,
            userData: ud)
        items[id] = si
    }
}

enum Fixture {
    static let library = "lib-movies"

    static func movie(_ n: Int, created: TimeInterval = 0, name: String? = nil, genres: [String] = [], year: Int? = nil, favorite: Bool = false, played: Bool = false, position: TimeInterval = 0) -> CatalogEntry {
        CatalogEntry(
            id: "m\(n)",
            libraryId: library,
            type: "Movie",
            mediaType: .movie,
            name: name ?? "Movie \(n)",
            sortName: name ?? "Movie \(String(format: "%03d", n))",
            productionYear: year,
            dateCreated: Date(timeIntervalSince1970: 1_600_000_000 + created + Double(n)),
            genres: genres.map { CatalogGenre(id: $0, name: $0) },
            userData: UserData(isFavorite: favorite, playbackPosition: position, isPlayed: played))
    }
}
