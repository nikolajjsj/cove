import Foundation
import GRDB
import Models
import os

/// Reads and writes the local catalogue.
///
/// This is the single source the UI reads from once local-first sync is on. Writes
/// come from the sync engine in page-sized transactions; reads are plain SQL over
/// the indexes migration 004 created for exactly the sorts and filters the UI has.
public final class CatalogRepository: Sendable {
    private let database: DatabaseManager
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Catalog")

    public init(database: DatabaseManager) {
        self.database = database
    }

    /// Everything a query needs to know about who is asking.
    public struct Scope: Hashable, Sendable {
        public let serverId: String
        public let userId: String
        public init(serverId: String, userId: String) {
            self.serverId = serverId
            self.userId = userId
        }
    }

    // MARK: - Writes from the sync engine

    /// Upsert one page of entries, and their user data, genres and studios, in a
    /// single transaction. Never delete-and-reinsert: that fires every observation
    /// and would lose `lastSeenInReconcile`.
    ///
    /// User data is written only for rows with **no pending outbox entry** for the
    /// field — the pending write is the truth until the server has acknowledged it.
    public func upsert(_ entries: [CatalogEntry], scope: Scope) async throws {
        guard !entries.isEmpty else { return }
        try await database.dbWriter.write { db in
            let pending = try Self.pendingOutboxFields(db, scope: scope)
            for entry in entries {
                let record = CatalogItemRecord(entry: entry, serverId: scope.serverId, userId: scope.userId)
                try Self.upsertItem(record, db)

                try db.execute(
                    sql: "DELETE FROM catalog_item_genres WHERE serverId = ? AND userId = ? AND itemId = ?",
                    arguments: [scope.serverId, scope.userId, entry.id])
                for genre in entry.genres {
                    try CatalogItemGenreRecord(
                        serverId: scope.serverId, userId: scope.userId, itemId: entry.id,
                        genreId: genre.id, genreName: genre.name
                    ).insert(db, onConflict: .replace)
                }

                try db.execute(
                    sql: "DELETE FROM catalog_item_studios WHERE serverId = ? AND userId = ? AND itemId = ?",
                    arguments: [scope.serverId, scope.userId, entry.id])
                for studio in entry.studios {
                    try CatalogItemStudioRecord(
                        serverId: scope.serverId, userId: scope.userId, itemId: entry.id,
                        studioName: studio
                    ).insert(db, onConflict: .replace)
                }

                if let userData = entry.userData {
                    try Self.upsertUserData(
                        userData, scope: scope, itemId: entry.id,
                        protecting: pending[entry.id] ?? [], db)
                }
            }
        }
    }

    /// Upsert user data alone — the user-data sweeps call this.
    public func upsertUserData(_ rows: [(itemId: String, userData: UserData)], scope: Scope) async throws {
        guard !rows.isEmpty else { return }
        try await database.dbWriter.write { db in
            let pending = try Self.pendingOutboxFields(db, scope: scope)
            for row in rows {
                // A sweep may name an item the catalogue does not hold yet (a fresh
                // add between passes). The FK forbids the orphan; skip, the next
                // catalogue pass brings the item and its user data together.
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId = ?)",
                    arguments: [scope.serverId, scope.userId, row.itemId]) ?? false
                guard exists else { continue }
                try Self.upsertUserData(
                    row.userData, scope: scope, itemId: row.itemId,
                    protecting: pending[row.itemId] ?? [], db)
            }
        }
    }

    private static func upsertItem(_ r: CatalogItemRecord, _ db: Database) throws {
        let set = CatalogItemRecord.syncedColumns
            .map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
        try db.execute(
            sql: """
                INSERT INTO catalog_items (
                    serverId, userId, itemId, libraryId, parentId, seriesId, seasonId, type,
                    mediaType, name, sortName, productionYear, premiereDate, dateCreated,
                    runTimeTicks, communityRating, criticRating, officialRating, indexNumber,
                    parentIndexNumber, seriesName, imageTags, lastSeenInReconcile
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(serverId, userId, itemId) DO UPDATE SET \(set)
                """,
            arguments: [
                r.serverId, r.userId, r.itemId, r.libraryId, r.parentId, r.seriesId, r.seasonId,
                r.type, r.mediaType, r.name, r.sortName, r.productionYear, r.premiereDate,
                r.dateCreated, r.runTimeTicks, r.communityRating, r.criticRating,
                r.officialRating, r.indexNumber, r.parentIndexNumber, r.seriesName, r.imageTags,
            ])
    }

    /// Fields with a pending outbox row, per item. Those fields are not overwritten
    /// by anything the server says until the flush has succeeded.
    private static func pendingOutboxFields(_ db: Database, scope: Scope) throws -> [String: Set<String>] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT itemId, field FROM user_data_outbox WHERE serverId = ? AND userId = ?",
            arguments: [scope.serverId, scope.userId])
        var out: [String: Set<String>] = [:]
        for row in rows {
            out[row["itemId"], default: []].insert(row["field"])
        }
        return out
    }

    private static func upsertUserData(
        _ u: UserData, scope: Scope, itemId: String, protecting pending: Set<String>, _ db: Database
    ) throws {
        // Build the SET list from what is *not* protected. If everything is
        // protected the row still needs to exist, so insert-or-ignore.
        var sets: [String] = []
        if !pending.contains("played") { sets += ["played = excluded.played", "playCount = excluded.playCount"] }
        if !pending.contains("favorite") { sets.append("isFavorite = excluded.isFavorite") }
        if !pending.contains("position") {
            sets += ["playbackPositionTicks = excluded.playbackPositionTicks", "lastPlayedDate = excluded.lastPlayedDate"]
        }
        let conflict = sets.isEmpty ? "DO NOTHING" : "DO UPDATE SET " + sets.joined(separator: ", ")
        try db.execute(
            sql: """
                INSERT INTO catalog_user_data (serverId, userId, itemId, played, playCount, isFavorite,
                    playbackPositionTicks, lastPlayedDate)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(serverId, userId, itemId) \(conflict)
                """,
            arguments: [
                scope.serverId, scope.userId, itemId, u.isPlayed, u.playCount, u.isFavorite,
                Int64(u.playbackPosition * 10_000_000), u.lastPlayedDate,
            ])
    }

    // MARK: - Reconciliation helpers

    public func itemIds(libraryId: String, scope: Scope) async throws -> Set<String> {
        try await database.dbWriter.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT itemId FROM catalog_items WHERE serverId = ? AND userId = ? AND libraryId = ?",
                arguments: [scope.serverId, scope.userId, libraryId]))
        }
    }

    /// Delete rows the server no longer lists. Cascades to user data, genres,
    /// studios and the search index. Never touches downloads or pinned detail rows.
    public func delete(itemIds: [String], scope: Scope) async throws {
        guard !itemIds.isEmpty else { return }
        try await database.dbWriter.write { db in
            for chunk in itemIds.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
                args += chunk
                try db.execute(
                    sql: "DELETE FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))",
                    arguments: StatementArguments(args))
            }
        }
    }

    public func markSeen(itemIds: [String], at date: Date, scope: Scope) async throws {
        guard !itemIds.isEmpty else { return }
        try await database.dbWriter.write { db in
            for chunk in itemIds.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [date, scope.serverId, scope.userId]
                args += chunk
                try db.execute(
                    sql: "UPDATE catalog_items SET lastSeenInReconcile = ? WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))",
                    arguments: StatementArguments(args))
            }
        }
    }

    public func deleteLibrary(libraryId: String, scope: Scope) async throws {
        try await database.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM catalog_items WHERE serverId = ? AND userId = ? AND libraryId = ?",
                arguments: [scope.serverId, scope.userId, libraryId])
        }
    }

    public func count(libraryId: String? = nil, scope: Scope) async throws -> Int {
        try await database.dbWriter.read { db in
            if let libraryId {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM catalog_items WHERE serverId = ? AND userId = ? AND libraryId = ?",
                    arguments: [scope.serverId, scope.userId, libraryId]) ?? 0
            }
            return try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM catalog_items WHERE serverId = ? AND userId = ?",
                arguments: [scope.serverId, scope.userId]) ?? 0
        }
    }

    // MARK: - Sync state

    public func syncState(scope: Scope, key: String) async throws -> SyncStateRecord {
        try await database.dbWriter.read { db in
            try SyncStateRecord.fetchOne(
                db,
                sql: "SELECT * FROM sync_state WHERE serverId = ? AND userId = ? AND scope = ?",
                arguments: [scope.serverId, scope.userId, key])
                ?? SyncStateRecord(serverId: scope.serverId, userId: scope.userId, scope: key)
        }
    }

    public func saveSyncState(_ state: SyncStateRecord) async throws {
        try await database.dbWriter.write { db in
            try state.save(db)
        }
    }

    /// Bootstrap writes a page and its next index in one transaction, so a kill
    /// between the two cannot leave them disagreeing.
    public func upsertBootstrapPage(_ entries: [CatalogEntry], nextIndex: Int, scope: Scope, key: String) async throws {
        try await upsert(entries, scope: scope)
        var state = try await syncState(scope: scope, key: key)
        state.bootstrapNextIndex = nextIndex
        state.lastRunAt = Date()
        try await saveSyncState(state)
    }

    // MARK: - Reads for the UI

    /// The grid query. Every `SortField` and every `FilterOptions` field the UI can
    /// set maps here; anything the server used to do is now a WHERE clause.
    public func pagedItems(
        libraryId: String,
        itemTypes: [String]?,
        sort: SortOptions,
        filter: FilterOptions,
        scope: Scope
    ) async throws -> PagedResult<MediaItem> {
        let query = CatalogQuery(libraryId: libraryId, itemTypes: itemTypes, sort: sort, filter: filter, scope: scope)
        return try await database.dbWriter.read { db in
            let total = try Int.fetchOne(db, sql: query.countSQL, arguments: query.arguments) ?? 0
            let rows = try Row.fetchAll(db, sql: query.pageSQL, arguments: query.pageArguments)
            let items = rows.map(Self.mediaItem(from:))
            return PagedResult(items: items, startIndex: filter.startIndex ?? 0, totalCount: total)
        }
    }

    /// Distinct genre names present in a library, for the filter menu.
    public func genres(libraryId: String, scope: Scope) async throws -> [String] {
        try await database.dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT g.genreName FROM catalog_item_genres g
                    JOIN catalog_items i ON i.serverId = g.serverId AND i.userId = g.userId AND i.itemId = g.itemId
                    WHERE g.serverId = ? AND g.userId = ? AND i.libraryId = ?
                    ORDER BY g.genreName COLLATE NOCASE
                    """,
                arguments: [scope.serverId, scope.userId, libraryId])
        }
    }

    public func item(id: String, scope: Scope) async throws -> MediaItem? {
        try await database.dbWriter.read { db in
            try Row.fetchOne(
                db,
                sql: CatalogQuery.selectSQL + " WHERE i.serverId = ? AND i.userId = ? AND i.itemId = ?",
                arguments: [scope.serverId, scope.userId, id]
            ).map(Self.mediaItem(from:))
        }
    }

    /// Lean `MediaItem` from a joined row. Detail-tier fields are nil by design.
    static func mediaItem(from row: Row) -> MediaItem {
        let userData: UserData? = row["ud_itemId"] == nil ? nil : UserData(
            isFavorite: row["isFavorite"] ?? false,
            playbackPosition: TimeInterval((row["playbackPositionTicks"] as Int64?) ?? 0) / 10_000_000,
            playCount: row["playCount"] ?? 0,
            isPlayed: row["played"] ?? false,
            lastPlayedDate: row["lastPlayedDate"])
        let genres: [String]? = (row["genreNames"] as String?).map {
            $0.split(separator: "\u{1F}").map(String.init)
        }
        return MediaItem(
            id: ItemID(row["itemId"]),
            title: row["name"],
            mediaType: MediaType(rawValue: row["mediaType"]) ?? .movie,
            dateAdded: row["dateCreated"],
            productionYear: row["productionYear"],
            genres: genres,
            runTimeTicks: row["runTimeTicks"],
            communityRating: row["communityRating"],
            officialRating: row["officialRating"],
            criticRating: row["criticRating"],
            premiereDate: row["premiereDate"],
            userData: userData,
            imageTags: CatalogItemRecord.decodeImageTags(row["imageTags"]),
            seriesName: row["seriesName"],
            seriesId: (row["seriesId"] as String?).map(ItemID.init),
            indexNumber: row["indexNumber"],
            parentIndexNumber: row["parentIndexNumber"])
    }
}

// MARK: - Query builder

/// Turns `SortOptions` + `FilterOptions` into SQL over the catalogue.
struct CatalogQuery {
    static let selectSQL = """
        SELECT i.*, u.itemId AS ud_itemId, u.played, u.playCount, u.isFavorite,
               u.playbackPositionTicks, u.lastPlayedDate,
               (SELECT group_concat(g.genreName, char(31)) FROM catalog_item_genres g
                 WHERE g.serverId = i.serverId AND g.userId = i.userId AND g.itemId = i.itemId) AS genreNames
        FROM catalog_items i
        LEFT JOIN catalog_user_data u
          ON u.serverId = i.serverId AND u.userId = i.userId AND u.itemId = i.itemId
        """

    private(set) var whereClauses: [String] = []
    private(set) var arguments: StatementArguments = []
    let orderSQL: String
    let limit: Int
    let offset: Int

    init(libraryId: String, itemTypes: [String]?, sort: SortOptions, filter: FilterOptions, scope: CatalogRepository.Scope) {
        var clauses = ["i.serverId = ?", "i.userId = ?", "i.libraryId = ?"]
        var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId, libraryId]

        if let itemTypes, !itemTypes.isEmpty {
            clauses.append("i.type IN (\(Array(repeating: "?", count: itemTypes.count).joined(separator: ",")))")
            args += itemTypes
        }
        if let favorite = filter.isFavorite {
            clauses.append(favorite ? "u.isFavorite = 1" : "COALESCE(u.isFavorite, 0) = 0")
        }
        if let played = filter.isPlayed {
            clauses.append(played ? "u.played = 1" : "COALESCE(u.played, 0) = 0")
        }
        if let years = filter.years, !years.isEmpty {
            clauses.append("i.productionYear IN (\(Array(repeating: "?", count: years.count).joined(separator: ",")))")
            args += years
        }
        if let rating = filter.minCommunityRating {
            clauses.append("i.communityRating >= ?")
            args.append(rating)
        }
        if let genres = filter.genres, !genres.isEmpty {
            let marks = Array(repeating: "?", count: genres.count).joined(separator: ",")
            clauses.append("""
                EXISTS (SELECT 1 FROM catalog_item_genres g WHERE g.serverId = i.serverId
                        AND g.userId = i.userId AND g.itemId = i.itemId AND g.genreName IN (\(marks)))
                """)
            args += genres
        }
        if let studios = filter.studios, !studios.isEmpty {
            let marks = Array(repeating: "?", count: studios.count).joined(separator: ",")
            clauses.append("""
                EXISTS (SELECT 1 FROM catalog_item_studios s WHERE s.serverId = i.serverId
                        AND s.userId = i.userId AND s.itemId = i.itemId AND s.studioName IN (\(marks)))
                """)
            args += studios
        }
        if let term = filter.searchTerm?.trimmingCharacters(in: .whitespaces), !term.isEmpty {
            // Prefix match on every token, diacritics folded by the tokenizer.
            let ftsQuery = term.split(separator: " ")
                .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
                .joined(separator: " ")
            clauses.append("i.rowid IN (SELECT rowid FROM catalog_items_fts WHERE catalog_items_fts MATCH ?)")
            args.append(ftsQuery)
        }

        whereClauses = clauses
        arguments = StatementArguments(args)
        orderSQL = Self.order(for: sort)
        limit = filter.limit ?? 40
        offset = filter.startIndex ?? 0
    }

    var countSQL: String {
        "SELECT COUNT(*) FROM catalog_items i LEFT JOIN catalog_user_data u ON u.serverId = i.serverId AND u.userId = i.userId AND u.itemId = i.itemId WHERE "
            + whereClauses.joined(separator: " AND ")
    }

    var pageSQL: String {
        Self.selectSQL + " WHERE " + whereClauses.joined(separator: " AND ")
            + " ORDER BY \(orderSQL) LIMIT ? OFFSET ?"
    }

    var pageArguments: StatementArguments {
        var a = arguments
        a += [limit, offset]
        return a
    }

    /// Ties are broken by sortName then itemId so paging over equal keys is stable.
    static func order(for sort: SortOptions) -> String {
        let dir = sort.order == .ascending ? "ASC" : "DESC"
        let primary: String
        switch sort.field {
        case .name: primary = "i.sortName COLLATE NOCASE \(dir)"
        case .dateAdded, .dateCreated: primary = "i.dateCreated \(dir)"
        case .datePlayed: primary = "u.lastPlayedDate \(dir) NULLS LAST"
        case .premiereDate: primary = "i.premiereDate \(dir) NULLS LAST"
        case .communityRating: primary = "i.communityRating \(dir) NULLS LAST"
        case .criticRating: primary = "i.criticRating \(dir) NULLS LAST"
        case .runtime: primary = "i.runTimeTicks \(dir) NULLS LAST"
        case .playCount: primary = "COALESCE(u.playCount, 0) \(dir)"
        case .random: return "random()"
        case .albumArtist, .album: primary = "i.sortName COLLATE NOCASE \(dir)"
        }
        return "\(primary), i.sortName COLLATE NOCASE ASC, i.itemId ASC"
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
