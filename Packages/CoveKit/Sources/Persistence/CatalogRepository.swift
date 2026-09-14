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
                    parentIndexNumber, seriesName, imageTags, lastSeenInReconcile, syncedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                ON CONFLICT(serverId, userId, itemId) DO UPDATE SET \(set)
                """,
            arguments: [
                r.serverId, r.userId, r.itemId, r.libraryId, r.parentId, r.seriesId, r.seasonId,
                r.type, r.mediaType, r.name, r.sortName, r.productionYear, r.premiereDate,
                r.dateCreated, r.runTimeTicks, r.communityRating, r.criticRating,
                r.officialRating, r.indexNumber, r.parentIndexNumber, r.seriesName, r.imageTags,
                r.syncedAt,
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

    // MARK: - Libraries

    /// Replace the saved library list for a scope. Called after every successful
    /// `/UserViews`; never on failure, since an empty list on a 5xx is not "no
    /// libraries".
    public func saveLibraries(_ libraries: [MediaLibrary], scope: Scope) async throws {
        try await database.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM catalog_libraries WHERE serverId = ? AND userId = ?",
                arguments: [scope.serverId, scope.userId])
            for (index, lib) in libraries.enumerated() {
                try CatalogLibraryRecord(
                    serverId: scope.serverId, userId: scope.userId, libraryId: lib.id.rawValue,
                    name: lib.name, collectionType: lib.collectionType?.rawValue, sortIndex: index
                ).insert(db)
            }
        }
    }

    public func libraries(scope: Scope) async throws -> [MediaLibrary] {
        try await database.dbWriter.read { db in
            try CatalogLibraryRecord.fetchAll(
                db,
                sql: "SELECT * FROM catalog_libraries WHERE serverId = ? AND userId = ? ORDER BY sortIndex",
                arguments: [scope.serverId, scope.userId]
            ).map(\.asLibrary)
        }
    }

    // MARK: - Artwork manifest

    /// What the prefetcher needs to build every artwork URL: id, server type and
    /// the image tags — nothing else. Newest first, so a fresh library's most
    /// recent additions are the first to be cached.
    public struct ArtworkRow: Sendable {
        public let itemId: String
        public let type: String
        public let imageTags: [ImageType: String]
    }

    public func artworkRows(scope: Scope, offset: Int, limit: Int) async throws -> [ArtworkRow] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT itemId, type, imageTags FROM catalog_items
                    WHERE serverId = ? AND userId = ? AND imageTags IS NOT NULL
                    ORDER BY dateCreated DESC, itemId LIMIT ? OFFSET ?
                    """,
                arguments: [scope.serverId, scope.userId, limit, offset]
            ).compactMap { row in
                guard let tags = CatalogItemRecord.decodeImageTags(row["imageTags"]) else { return nil }
                return ArtworkRow(itemId: row["itemId"], type: row["type"], imageTags: tags)
            }
        }
    }

    // MARK: - Collections

    /// Replace a BoxSet's members, in the server's order. Ids the catalogue does
    /// not hold (another library, an unsynced type) are stored anyway so a later
    /// sync can light them up; `collectionItems` joins them away until then.
    public func replaceCollectionMembers(collectionId: String, itemIds: [String], scope: Scope) async throws {
        try await database.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM catalog_collection_items WHERE serverId = ? AND userId = ? AND collectionId = ?",
                arguments: [scope.serverId, scope.userId, collectionId])
            for (index, id) in itemIds.enumerated() {
                try CatalogCollectionItemRecord(
                    serverId: scope.serverId, userId: scope.userId, collectionId: collectionId,
                    itemId: id, sortIndex: index
                ).insert(db, onConflict: .replace)
            }
        }
    }

    /// A BoxSet's members that the catalogue knows, in the server's order.
    public func collectionItems(collectionId: String, scope: Scope) async throws -> [MediaItem] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: CatalogQuery.selectSQL + """
                     JOIN catalog_collection_items c
                       ON c.serverId = i.serverId AND c.userId = i.userId AND c.itemId = i.itemId
                     WHERE i.serverId = ? AND i.userId = ? AND c.collectionId = ?
                     ORDER BY c.sortIndex
                    """,
                arguments: [scope.serverId, scope.userId, collectionId]
            ).map(Self.mediaItem(from:))
        }
    }

    /// Every BoxSet the catalogue holds, optionally within one library — the set
    /// whose membership the sync engine refreshes.
    public func collectionIds(libraryId: String? = nil, scope: Scope) async throws -> [String] {
        try await database.dbWriter.read { db in
            var sql = "SELECT itemId FROM catalog_items WHERE serverId = ? AND userId = ? AND type = 'BoxSet'"
            var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
            if let libraryId {
                sql += " AND libraryId = ?"
                args.append(libraryId)
            }
            return try String.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    // MARK: - User-data sweep helpers

    /// Items the catalogue thinks are in progress. Anything here that a Resume
    /// sweep does not return has finished or been reset elsewhere.
    public func inProgressIds(scope: Scope) async throws -> Set<String> {
        try await database.dbWriter.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT itemId FROM catalog_user_data WHERE serverId = ? AND userId = ? AND playbackPositionTicks > 0 AND played = 0",
                arguments: [scope.serverId, scope.userId]))
        }
    }

    public func favoriteIds(scope: Scope) async throws -> Set<String> {
        try await database.dbWriter.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT itemId FROM catalog_user_data WHERE serverId = ? AND userId = ? AND isFavorite = 1",
                arguments: [scope.serverId, scope.userId]))
        }
    }

    /// Set the favourite flag on exactly `ids`; clear it everywhere else — except
    /// where a favourite write is still pending in the outbox.
    public func replaceFavorites(with ids: Set<String>, scope: Scope) async throws {
        try await database.dbWriter.write { db in
            let pending = try Self.pendingOutboxFields(db, scope: scope)
                .filter { $0.value.contains("favorite") }.map(\.key)
            let protect = Array(repeating: "?", count: pending.count).joined(separator: ",")
            let protectClause = pending.isEmpty ? "" : " AND itemId NOT IN (\(protect))"
            var clearArgs: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
            clearArgs += pending
            try db.execute(
                sql: "UPDATE catalog_user_data SET isFavorite = 0 WHERE serverId = ? AND userId = ? AND isFavorite = 1\(protectClause)",
                arguments: StatementArguments(clearArgs))
            for chunk in Array(ids).chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
                args += chunk
                args += pending
                try db.execute(
                    sql: "UPDATE catalog_user_data SET isFavorite = 1 WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))\(protectClause)",
                    arguments: StatementArguments(args))
            }
        }
    }

    // MARK: - Derived feeds

    /// Continue Watching, derived locally so Home does not change shape when the
    /// connection does.
    public func resumeItems(scope: Scope, limit: Int = 20) async throws -> [MediaItem] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: CatalogQuery.selectSQL + """
                     WHERE i.serverId = ? AND i.userId = ? AND u.playbackPositionTicks > 0 AND u.played = 0
                       AND i.type IN ('Movie', 'Episode')
                     ORDER BY u.lastPlayedDate DESC NULLS LAST LIMIT ?
                    """,
                arguments: [scope.serverId, scope.userId, limit]
            ).map(Self.mediaItem(from:))
        }
    }

    /// Next Up: per series with a played episode, the first unplayed episode after
    /// the latest played one, specials excluded. Series ordered by most recent
    /// activity. Diverges from the server on AiredEpisodeOrder and rewatching,
    /// by design.
    public func nextUp(scope: Scope, limit: Int = 20) async throws -> [MediaItem] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    WITH played AS (
                        SELECT i.seriesId,
                               MAX(i.parentIndexNumber * 100000 + i.indexNumber) AS lastKey,
                               MAX(u.lastPlayedDate) AS lastPlayed
                        FROM catalog_items i
                        JOIN catalog_user_data u ON u.serverId = i.serverId AND u.userId = i.userId AND u.itemId = i.itemId
                        WHERE i.serverId = ? AND i.userId = ? AND i.type = 'Episode' AND u.played = 1
                          AND i.parentIndexNumber > 0 AND i.seriesId IS NOT NULL
                        GROUP BY i.seriesId
                    ),
                    candidate AS (
                        SELECT i.itemId, p.lastPlayed,
                               ROW_NUMBER() OVER (PARTITION BY i.seriesId ORDER BY i.parentIndexNumber, i.indexNumber) AS rn
                        FROM catalog_items i
                        JOIN played p ON p.seriesId = i.seriesId
                        LEFT JOIN catalog_user_data u ON u.serverId = i.serverId AND u.userId = i.userId AND u.itemId = i.itemId
                        WHERE i.serverId = ? AND i.userId = ? AND i.type = 'Episode' AND i.parentIndexNumber > 0
                          AND COALESCE(u.played, 0) = 0
                          AND (i.parentIndexNumber * 100000 + i.indexNumber) > p.lastKey
                    )
                    \(CatalogQuery.selectSQL)
                    JOIN candidate c ON c.itemId = i.itemId
                    WHERE i.serverId = ? AND i.userId = ? AND c.rn = 1
                    ORDER BY c.lastPlayed DESC NULLS LAST LIMIT ?
                    """,
                arguments: [scope.serverId, scope.userId, scope.serverId, scope.userId, scope.serverId, scope.userId, limit]
            ).map(Self.mediaItem(from:))
        }
    }

    /// Cross-library recently added: Movies and Series only, so episodes collapse
    /// into their series.
    public func recentlyAdded(scope: Scope, limit: Int = 20) async throws -> [MediaItem] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: CatalogQuery.selectSQL + """
                     WHERE i.serverId = ? AND i.userId = ? AND i.type IN ('Movie', 'Series')
                     ORDER BY i.dateCreated DESC, i.itemId LIMIT ?
                    """,
                arguments: [scope.serverId, scope.userId, limit]
            ).map(Self.mediaItem(from:))
        }
    }

    /// A library's newest items, for the Home rail.
    public func latest(libraryId: String, itemTypes: [String]?, scope: Scope, limit: Int = 20) async throws -> [MediaItem] {
        try await pagedItems(
            libraryId: libraryId, itemTypes: itemTypes,
            sort: SortOptions(field: .dateAdded, order: .descending),
            filter: FilterOptions(limit: limit, startIndex: 0), scope: scope
        ).items
    }

    /// Paged scope-wide search with a total, for See All.
    public func searchPaged(term: String, filter: FilterOptions, scope: Scope) async throws -> PagedResult<MediaItem> {
        let full = FilterOptions(
            genres: filter.genres, years: filter.years, isFavorite: filter.isFavorite,
            isPlayed: filter.isPlayed, limit: filter.limit ?? 40, startIndex: filter.startIndex ?? 0,
            searchTerm: term, includeItemTypes: filter.includeItemTypes ?? ["Movie", "Series", "Episode"],
            minCommunityRating: filter.minCommunityRating)
        let query = CatalogQuery(libraryId: nil, itemTypes: full.includeItemTypes,
                                 sort: SortOptions(field: .name, order: .ascending), filter: full, scope: scope)
        return try await database.dbWriter.read { db in
            let total = try Int.fetchOne(db, sql: query.countSQL, arguments: query.arguments) ?? 0
            let items = try Row.fetchAll(db, sql: query.pageSQL, arguments: query.pageArguments).map(Self.mediaItem(from:))
            return PagedResult(items: items, startIndex: full.startIndex ?? 0, totalCount: total)
        }
    }

    /// Scope-wide search over the FTS index, with the same filters the grid has.
    public func search(term: String, filter: FilterOptions, scope: Scope) async throws -> [MediaItem] {
        let full = FilterOptions(
            genres: filter.genres, years: filter.years, isFavorite: filter.isFavorite,
            isPlayed: filter.isPlayed, limit: filter.limit ?? 60, startIndex: filter.startIndex ?? 0,
            searchTerm: term, includeItemTypes: filter.includeItemTypes ?? ["Movie", "Series", "Episode"],
            minCommunityRating: filter.minCommunityRating)
        let query = CatalogQuery(libraryId: nil, itemTypes: full.includeItemTypes,
                                 sort: SortOptions(field: .name, order: .ascending), filter: full, scope: scope)
        return try await database.dbWriter.read { db in
            try Row.fetchAll(db, sql: query.pageSQL, arguments: query.pageArguments).map(Self.mediaItem(from:))
        }
    }

    // MARK: - Detail tier

    /// The cached full item, with user data overlaid from `catalog_user_data`
    /// (the truth, outbox-protected) rather than whatever the JSON captured.
    /// Touches `lastAccessedAt` so eviction is LRU.
    public func detail(id: String, scope: Scope) async throws -> MediaItem? {
        try await database.dbWriter.write { db in
            guard let record = try CatalogItemDetailRecord.fetchOne(
                db,
                sql: "SELECT * FROM catalog_item_details WHERE serverId = ? AND userId = ? AND itemId = ?",
                arguments: [scope.serverId, scope.userId, id]),
                var item = record.item
            else { return nil }
            try db.execute(
                sql: "UPDATE catalog_item_details SET lastAccessedAt = ? WHERE serverId = ? AND userId = ? AND itemId = ?",
                arguments: [Date(), scope.serverId, scope.userId, id])
            if let ud = try CatalogUserDataRecord.fetchOne(
                db,
                sql: "SELECT * FROM catalog_user_data WHERE serverId = ? AND userId = ? AND itemId = ?",
                arguments: [scope.serverId, scope.userId, id]) {
                item.userData = ud.asUserData
            }
            return item
        }
    }

    /// A cached detail and whether the server has changed the item since.
    public struct CachedDetail: Sendable {
        public let item: MediaItem
        /// The catalogue row was re-synced after this detail was fetched, so the
        /// server saved new metadata for the item and the JSON is behind it.
        public let isStale: Bool
    }

    /// `detail(id:)` plus the staleness verdict, in one call, for the view path.
    public func cachedDetail(id: String, scope: Scope) async throws -> CachedDetail? {
        guard let item = try await detail(id: id, scope: scope) else { return nil }
        let stale = try await database.dbWriter.read { db in
            // Both columns are GRDB datetime text in UTC, so string order is time order.
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT i.syncedAt > d.updatedAt FROM catalog_item_details d
                    JOIN catalog_items i ON i.serverId = d.serverId AND i.userId = d.userId AND i.itemId = d.itemId
                    WHERE d.serverId = ? AND d.userId = ? AND d.itemId = ?
                    """,
                arguments: [scope.serverId, scope.userId, id]) ?? false
        }
        return CachedDetail(item: item, isStale: stale)
    }

    /// Save a full item. `pinned` is an explicit pin; a live download protects a
    /// row regardless (see `evictDetails`).
    public func saveDetail(_ item: MediaItem, pinned: Bool = false, scope: Scope) async throws {
        let record = try CatalogItemDetailRecord(item: item, serverId: scope.serverId, userId: scope.userId, pinned: pinned)
        try await database.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO catalog_item_details (serverId, userId, itemId, json, pinned, lastAccessedAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(serverId, userId, itemId) DO UPDATE SET
                        json = excluded.json,
                        pinned = catalog_item_details.pinned OR excluded.pinned,
                        lastAccessedAt = excluded.lastAccessedAt,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [record.serverId, record.userId, record.itemId, record.json, record.pinned, record.lastAccessedAt, record.updatedAt])
            // Keep the user-data table in step if the item brought some and no
            // write is pending for it.
            if let ud = item.userData {
                let pending = try Self.pendingOutboxFields(db, scope: scope)[item.id.rawValue] ?? []
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId = ?)",
                    arguments: [scope.serverId, scope.userId, item.id.rawValue]) ?? false
                if exists {
                    try Self.upsertUserData(ud, scope: scope, itemId: item.id.rawValue, protecting: pending, db)
                }
            }
        }
    }

    public func setPinned(_ pinned: Bool, itemIds: [String], scope: Scope) async throws {
        guard !itemIds.isEmpty else { return }
        try await database.dbWriter.write { db in
            for chunk in itemIds.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [pinned, scope.serverId, scope.userId]
                args += chunk
                try db.execute(
                    sql: "UPDATE catalog_item_details SET pinned = ? WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))",
                    arguments: StatementArguments(args))
            }
        }
    }

    /// Bytes held by detail rows that eviction is allowed to remove.
    public func evictableDetailBytes(scope: Scope) async throws -> Int {
        try await database.dbWriter.read { db in
            try Int.fetchOne(db, sql: Self.evictableSQL(select: "COALESCE(SUM(LENGTH(d.json)), 0)"),
                             arguments: [scope.serverId, scope.userId]) ?? 0
        }
    }

    /// LRU-evict unprotected detail rows until the evictable set is under `budgetBytes`.
    /// A row is protected if it is pinned **or** a `downloads` row exists for its
    /// item — the join is what makes forgetting to unpin harmless.
    /// Returns the number of rows removed.
    public func evictDetails(budgetBytes: Int, scope: Scope) async throws -> Int {
        try await database.dbWriter.write { db in
            var total = try Int.fetchOne(db, sql: Self.evictableSQL(select: "COALESCE(SUM(LENGTH(d.json)), 0)"),
                                         arguments: [scope.serverId, scope.userId]) ?? 0
            guard total > budgetBytes else { return 0 }
            let victims = try Row.fetchAll(
                db,
                sql: Self.evictableSQL(select: "d.itemId, LENGTH(d.json) AS bytes") + " ORDER BY d.lastAccessedAt ASC",
                arguments: [scope.serverId, scope.userId])
            var removed: [String] = []
            for row in victims {
                guard total > budgetBytes else { break }
                removed.append(row["itemId"])
                total -= (row["bytes"] as Int?) ?? 0
            }
            for chunk in removed.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
                args += chunk
                try db.execute(
                    sql: "DELETE FROM catalog_item_details WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))",
                    arguments: StatementArguments(args))
            }
            return removed.count
        }
    }

    private static func evictableSQL(select: String) -> String {
        """
        SELECT \(select) FROM catalog_item_details d
        WHERE d.serverId = ? AND d.userId = ? AND d.pinned = 0
          AND NOT EXISTS (SELECT 1 FROM downloads w WHERE w.serverId = d.serverId AND w.itemId = d.itemId)
        """
    }

    // MARK: - Lookups the UI needs beyond paging

    public func userData(itemId: String, scope: Scope) async throws -> UserData? {
        try await database.dbWriter.read { db in
            try CatalogUserDataRecord.fetchOne(
                db,
                sql: "SELECT * FROM catalog_user_data WHERE serverId = ? AND userId = ? AND itemId = ?",
                arguments: [scope.serverId, scope.userId, itemId])?.asUserData
        }
    }

    /// Which of `ids` the catalogue no longer holds — orphaned downloads, once a
    /// library has bootstrapped.
    public func missingIds(among ids: [String], scope: Scope) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        return try await database.dbWriter.read { db in
            var present = Set<String>()
            for chunk in ids.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
                args += chunk
                present.formUnion(try String.fetchAll(
                    db,
                    sql: "SELECT itemId FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId IN (\(marks))",
                    arguments: StatementArguments(args)))
            }
            return Set(ids).subtracting(present)
        }
    }

    /// Seasons of a series, from the catalogue's Season rows.
    public func seasons(seriesId: String, scope: Scope) async throws -> [Season] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT i.itemId, i.name, i.indexNumber,
                           (SELECT COUNT(*) FROM catalog_items e WHERE e.serverId = i.serverId AND e.userId = i.userId
                              AND e.type = 'Episode' AND e.seasonId = i.itemId) AS episodeCount
                    FROM catalog_items i
                    WHERE i.serverId = ? AND i.userId = ? AND i.type = 'Season' AND i.seriesId = ?
                    ORDER BY i.indexNumber
                    """,
                arguments: [scope.serverId, scope.userId, seriesId]
            ).map { row in
                Season(
                    id: ItemID(row["itemId"]), seriesId: ItemID(seriesId),
                    seasonNumber: row["indexNumber"] ?? 0, title: row["name"],
                    episodeCount: row["episodeCount"])
            }
        }
    }

    /// Episodes of a season. Overview comes from the detail cache when the
    /// episode has ever been fetched; the lean row does not carry it.
    public func episodes(seasonId: String, scope: Scope) async throws -> [Episode] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT i.itemId, i.seriesId, i.seasonId, i.indexNumber, i.parentIndexNumber, i.name, i.runTimeTicks,
                           u.itemId AS ud_itemId, u.played, u.playCount, u.isFavorite, u.playbackPositionTicks, u.lastPlayedDate,
                           json_extract(d.json, '$.overview') AS overview
                    FROM catalog_items i
                    LEFT JOIN catalog_user_data u ON u.serverId = i.serverId AND u.userId = i.userId AND u.itemId = i.itemId
                    LEFT JOIN catalog_item_details d ON d.serverId = i.serverId AND d.userId = i.userId AND d.itemId = i.itemId
                    WHERE i.serverId = ? AND i.userId = ? AND i.type = 'Episode' AND i.seasonId = ?
                    ORDER BY i.indexNumber
                    """,
                arguments: [scope.serverId, scope.userId, seasonId]
            ).map { row in
                let ud: UserData? = row["ud_itemId"] == nil ? nil : UserData(
                    isFavorite: row["isFavorite"] ?? false,
                    playbackPosition: TimeInterval((row["playbackPositionTicks"] as Int64?) ?? 0) / 10_000_000,
                    playCount: row["playCount"] ?? 0,
                    isPlayed: row["played"] ?? false,
                    lastPlayedDate: row["lastPlayedDate"])
                return Episode(
                    id: ItemID(row["itemId"]),
                    seriesId: (row["seriesId"] as String?).map(ItemID.init),
                    seasonId: (row["seasonId"] as String?).map(ItemID.init),
                    episodeNumber: row["indexNumber"],
                    seasonNumber: row["parentIndexNumber"],
                    title: row["name"],
                    overview: row["overview"],
                    runtime: (row["runTimeTicks"] as Int64?).map { TimeInterval($0) / 10_000_000 },
                    userData: ud)
            }
        }
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

    /// Distinct studio names present in a library, for the studio list.
    public func studios(libraryId: String, scope: Scope) async throws -> [String] {
        try await database.dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT s.studioName FROM catalog_item_studios s
                    JOIN catalog_items i ON i.serverId = s.serverId AND i.userId = s.userId AND i.itemId = s.itemId
                    WHERE s.serverId = ? AND s.userId = ? AND i.libraryId = ?
                    ORDER BY s.studioName COLLATE NOCASE
                    """,
                arguments: [scope.serverId, scope.userId, libraryId])
        }
    }

    /// The episode that follows `itemId` in its series — next in the same season,
    /// else the first of the next season. Specials (season 0) are skipped, as
    /// Next Up does. Nil for a non-episode or the last episode.
    public func nextEpisode(after itemId: String, scope: Scope) async throws -> MediaItem? {
        try await database.dbWriter.read { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT seriesId, parentIndexNumber, indexNumber FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId = ? AND type = 'Episode'",
                arguments: [scope.serverId, scope.userId, itemId]),
                let seriesId: String = current["seriesId"]
            else { return nil }
            let season: Int = current["parentIndexNumber"] ?? 0
            let episode: Int = current["indexNumber"] ?? 0
            return try Row.fetchOne(
                db,
                sql: CatalogQuery.selectSQL + """
                     WHERE i.serverId = ? AND i.userId = ? AND i.type = 'Episode' AND i.seriesId = ?
                       AND i.parentIndexNumber > 0
                       AND (i.parentIndexNumber * 100000 + COALESCE(i.indexNumber, 0)) > ?
                     ORDER BY i.parentIndexNumber, i.indexNumber LIMIT 1
                    """,
                arguments: [scope.serverId, scope.userId, seriesId, season * 100000 + episode]
            ).map(Self.mediaItem(from:))
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

    init(libraryId: String?, itemTypes: [String]?, sort: SortOptions, filter: FilterOptions, scope: CatalogRepository.Scope) {
        var clauses = ["i.serverId = ?", "i.userId = ?"]
        var args: [any DatabaseValueConvertible] = [scope.serverId, scope.userId]
        if let libraryId {
            clauses.append("i.libraryId = ?")
            args.append(libraryId)
        }

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
        }
        return "\(primary), i.sortName COLLATE NOCASE ASC, i.itemId ASC"
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
