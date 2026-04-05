import Foundation
import GRDB
import Models
import os

/// Manages the GRDB database lifecycle, migrations, and provides access to the database.
public final class DatabaseManager: Sendable {
    /// The underlying GRDB database writer.
    /// `DatabasePool` for file-backed databases, `DatabaseQueue` for in-memory (testing).
    public let dbWriter: any DatabaseWriter

    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "Persistence")

    /// Initialize with a database at the given path.
    /// Creates the database file and parent directories if needed, then runs all migrations.
    public init(path: String) throws {
        logger.info("Opening database at \(path)")

        // Ensure the directory exists
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

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

        try migrator.migrate(dbWriter)
        logger.info("Database migrations complete")
    }

    /// The default database path in Application Support.
    public static var defaultPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dbDirectory = appSupport.appendingPathComponent(
            "com.nikolajjsj.jellyfin", isDirectory: true)
        return dbDirectory.appendingPathComponent("cove.db").path
    }
}
