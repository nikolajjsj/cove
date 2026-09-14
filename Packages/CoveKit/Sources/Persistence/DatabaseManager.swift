import Foundation
import GRDB
import Models
import os

/// Manages the GRDB database lifecycle, migrations, and provides access to the database.
public final class DatabaseManager: Sendable {
    /// The underlying GRDB database writer.
    /// `DatabasePool` for file-backed databases, `DatabaseQueue` for in-memory (testing).
    public let dbWriter: any DatabaseWriter

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Persistence")

    /// Initialize with a database at the given path.
    /// Creates the database file and parent directories if needed, then runs all migrations.
    public init(path: String) throws {
        logger.info("Opening database at \(path)")

        // Ensure the directory exists
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbWriter = try DatabasePool(path: path, configuration: config)
        try runMigrations()
    }

    /// Initialize with an in-memory database (for testing).
    /// Uses `DatabaseQueue` because `DatabasePool` requires WAL mode,
    /// which is not supported for in-memory databases.
    public init() throws {
        logger.info("Opening in-memory database")
        var config = Configuration()
        config.foreignKeysEnabled = true

        dbWriter = try DatabaseQueue(configuration: config)
        try runMigrations()
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()

        // In debug builds, always re-run migrations from scratch for easier development
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("001_initial") { db in
            // servers table
            try db.create(table: "servers") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("serverType", .text).notNull()
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }

        migrator.registerMigration("002_downloads") { db in
            // downloads table — tracks queued, in-progress, and completed media downloads
            try db.create(table: "downloads") { t in
                t.primaryKey("id", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("mediaType", .text).notNull()
                t.column("state", .text).notNull()
                t.column("progress", .double).notNull().defaults(to: 0.0)
                t.column("totalBytes", .integer).notNull().defaults(to: 0)
                t.column("downloadedBytes", .integer).notNull().defaults(to: 0)
                t.column("localFilePath", .text)
                t.column("remoteURL", .text).notNull()
                t.column("parentId", .text)
                t.column("artworkURL", .text)
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("completedAt", .datetime)
            }

            // Index for fast lookups by server
            try db.create(
                index: "downloads_on_serverId",
                on: "downloads",
                columns: ["serverId"]
            )

            // Index for fast lookups by state (e.g. fetching all queued downloads)
            try db.create(
                index: "downloads_on_state",
                on: "downloads",
                columns: ["state"]
            )

            // Unique index to prevent duplicate downloads of the same item on the same server
            try db.create(
                index: "downloads_on_itemId_serverId",
                on: "downloads",
                columns: ["itemId", "serverId"],
                unique: true
            )

            // offline_playback_reports table — queued playback position reports to sync when online
            try db.create(table: "offline_playback_reports") { t in
                t.primaryKey("id", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("positionTicks", .integer).notNull()
                t.column("eventType", .text).notNull()
                t.column("timestamp", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("isSynced", .boolean).notNull().defaults(to: false)
            }

            // Index for fetching unsent reports by server
            try db.create(
                index: "offline_playback_reports_on_serverId_isSynced",
                on: "offline_playback_reports",
                columns: ["serverId", "isSynced"]
            )
        }

        migrator.registerMigration("003_offline_redesign") { db in
            // offline_metadata table — cached Jellyfin metadata for offline browsing
            try db.create(table: "offline_metadata") { t in
                t.column("itemId", .text).notNull()
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("mediaType", .text).notNull()
                t.column("metadataJSON", .blob).notNull()
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.primaryKey(["itemId", "serverId"])
            }

            // Index for filtered lookups by server and media type
            try db.create(
                index: "offline_metadata_on_serverId_mediaType",
                on: "offline_metadata",
                columns: ["serverId", "mediaType"]
            )

            // download_groups table — logical grouping of downloads (e.g. a season or album)
            try db.create(table: "download_groups") { t in
                t.primaryKey("id", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("mediaType", .text).notNull()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Unique index to prevent duplicate groups for the same item on the same server
            try db.create(
                index: "download_groups_on_itemId_serverId",
                on: "download_groups",
                columns: ["itemId", "serverId"],
                unique: true
            )

            // Index for fast lookups by server
            try db.create(
                index: "download_groups_on_serverId",
                on: "download_groups",
                columns: ["serverId"]
            )

            // Add groupId column to downloads table
            try db.alter(table: "downloads") { t in
                t.add(column: "groupId", .text)
                    .references("download_groups", onDelete: .setNull)
            }

            // Index for fast group lookups on downloads
            try db.create(
                index: "downloads_on_groupId",
                on: "downloads",
                columns: ["groupId"]
            )
        }

        migrator.registerMigration("004_catalog") { db in
            // Every catalogue table is keyed by (serverId, userId, itemId), not
            // (serverId, itemId): what /Items returns is filtered per user by library
            // access and parental controls, so two users on one server hold two
            // different catalogues. Retrofitting a key column is the worst migration
            // there is; it is in the key from the start.

            try db.create(table: "catalog_items") { t in
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("userId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("libraryId", .text).notNull()
                t.column("parentId", .text)
                t.column("seriesId", .text)
                t.column("seasonId", .text)
                t.column("type", .text).notNull()
                t.column("mediaType", .text).notNull()
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull()
                t.column("productionYear", .integer)
                t.column("premiereDate", .datetime)
                t.column("dateCreated", .datetime).notNull()
                t.column("runTimeTicks", .integer)
                t.column("communityRating", .double)
                t.column("criticRating", .double)
                t.column("officialRating", .text)
                t.column("indexNumber", .integer)
                t.column("parentIndexNumber", .integer)
                t.column("seriesName", .text)
                // JSON {imageType: tag}. The tag is what busts Nuke's URL-keyed cache.
                t.column("imageTags", .text)
                // Reconcile stamps rows it saw; the rest are the phantoms.
                t.column("lastSeenInReconcile", .datetime)
                t.primaryKey(["serverId", "userId", "itemId"])
            }

            // One index per sort the UI actually offers (Models.SortField), each
            // leading with the columns every grid query constrains on.
            for column in [
                "sortName", "dateCreated", "premiereDate", "communityRating",
                "criticRating", "runTimeTicks", "productionYear",
            ] {
                try db.create(
                    index: "catalog_items_on_library_type_\(column)",
                    on: "catalog_items",
                    columns: ["serverId", "userId", "libraryId", "type", column])
            }
            try db.create(
                index: "catalog_items_on_series_order",
                on: "catalog_items",
                columns: ["serverId", "userId", "seriesId", "parentIndexNumber", "indexNumber"])
            try db.create(
                index: "catalog_items_on_reconcile",
                on: "catalog_items",
                columns: ["serverId", "userId", "libraryId", "lastSeenInReconcile"])

            // Separate table on purpose: its own sync cadence, a far higher change
            // rate, and writing it must not rewrite catalogue rows and wake every
            // observation in the app.
            try db.create(table: "catalog_user_data") { t in
                t.column("serverId", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("played", .boolean).notNull().defaults(to: false)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("playbackPositionTicks", .integer).notNull().defaults(to: 0)
                t.column("lastPlayedDate", .datetime)
                t.primaryKey(["serverId", "userId", "itemId"])
                t.foreignKey(
                    ["serverId", "userId", "itemId"],
                    references: "catalog_items",
                    columns: ["serverId", "userId", "itemId"],
                    onDelete: .cascade)
            }
            try db.create(
                index: "catalog_user_data_on_last_played",
                on: "catalog_user_data",
                columns: ["serverId", "userId", "lastPlayedDate"])
            try db.create(
                index: "catalog_user_data_on_favorite",
                on: "catalog_user_data",
                columns: ["serverId", "userId", "isFavorite"])
            try db.create(
                index: "catalog_user_data_on_played",
                on: "catalog_user_data",
                columns: ["serverId", "userId", "played"])

            // Genre and studio are grid filters today, so they live at catalogue tier.
            // People are not, so they stay in the detail tier.
            try db.create(table: "catalog_item_genres") { t in
                t.column("serverId", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("genreId", .text).notNull()
                t.column("genreName", .text).notNull()
                t.primaryKey(["serverId", "userId", "itemId", "genreId"])
                t.foreignKey(
                    ["serverId", "userId", "itemId"],
                    references: "catalog_items",
                    columns: ["serverId", "userId", "itemId"],
                    onDelete: .cascade)
            }
            try db.create(
                index: "catalog_item_genres_on_name",
                on: "catalog_item_genres",
                columns: ["serverId", "userId", "genreName", "itemId"])

            try db.create(table: "catalog_item_studios") { t in
                t.column("serverId", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("studioName", .text).notNull()
                t.primaryKey(["serverId", "userId", "itemId", "studioName"])
                t.foreignKey(
                    ["serverId", "userId", "itemId"],
                    references: "catalog_items",
                    columns: ["serverId", "userId", "itemId"],
                    onDelete: .cascade)
            }

            // External-content FTS5 over the catalogue, kept in step by triggers so it
            // cannot drift. remove_diacritics so "Amelie" finds "Amélie".
            try db.create(virtualTable: "catalog_items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "catalog_items")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("name")
                t.column("sortName")
                t.column("seriesName")
            }

            // Per (server, user, scope). Cursors are server time from the Date
            // header — never the device clock.
            try db.create(table: "sync_state") { t in
                t.column("serverId", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("scope", .text).notNull()
                t.column("cursor", .datetime)
                t.column("bootstrapNextIndex", .integer).notNull().defaults(to: 0)
                t.column("bootstrapComplete", .boolean).notNull().defaults(to: false)
                t.column("lastRunAt", .datetime)
                t.column("lastError", .text)
                t.primaryKey(["serverId", "userId", "scope"])
            }

            // Pending user-data writes. At most one row per (item, field): a later
            // write for the same pair replaces the earlier one, so six offline
            // toggles reach the server as one request.
            try db.create(table: "user_data_outbox") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("serverId", .text).notNull()
                t.column("userId", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("field", .text).notNull()
                t.column("value", .text).notNull()
                t.column("occurredAt", .datetime).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastAttemptAt", .datetime)
                t.column("lastError", .text)
                t.uniqueKey(["serverId", "userId", "itemId", "field"])
            }

            // The detail cache grows a pin and an access time. Downloads pin; the
            // eviction pass never touches a pinned row.
            try db.alter(table: "offline_metadata") { t in
                t.add(column: "pinned", .boolean).notNull().defaults(to: false)
                t.add(column: "lastAccessedAt", .datetime)
            }
        }

        migrator.registerMigration("005_catalog_libraries") { db in
            // The library list itself. Without it, an unreachable server leaves the
            // app with nothing to open even though every item is cached locally.
            try db.create(table: "catalog_libraries") { t in
                t.column("serverId", .text).notNull()
                    .references("servers", onDelete: .cascade)
                t.column("userId", .text).notNull()
                t.column("libraryId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("collectionType", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.primaryKey(["serverId", "userId", "libraryId"])
            }
        }

        try migrator.migrate(dbWriter)
        logger.info("Database migrations complete")
    }

    /// The default database path in Application Support.
    public static var defaultPath: String {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            return URL.temporaryDirectory
                .appending(path: "cove.db")
                .path(percentEncoded: false)
        }
        let dbDirectory = appSupport.appending(
            path: AppConstants.bundleIdentifier, directoryHint: .isDirectory)
        return dbDirectory.appending(path: "cove.db").path(percentEncoded: false)
    }
}
