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
