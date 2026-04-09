import Foundation
import GRDB
import Models
import os

/// Repository for persisting and querying download groups.
///
/// Provides CRUD operations for managing logical groups of related downloads
/// (e.g., all episodes in a season, all tracks in an album).
/// All methods are async and safe to call from any concurrency context.
public final class DownloadGroupRepository: Sendable {
    private let dbWriter: any DatabaseWriter
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Persistence")

    public init(database: DatabaseManager) {
        self.dbWriter = database.dbWriter
    }

    // MARK: - Save

    /// Save a download group (insert or update).
    public func save(_ group: DownloadGroup) async throws {
        let record = DownloadGroupRecord(from: group)
        try await dbWriter.write { db in
            try record.save(db)
        }
        logger.info("Saved download group: \(group.title) [\(group.id)]")
    }

    // MARK: - Fetch

    /// Fetch a group by its unique ID.
    public func fetch(id: String) async throws -> DownloadGroup? {
        try await dbWriter.read { db in
            let record = try DownloadGroupRecord.fetchOne(db, key: id)
            return record?.toDownloadGroup()
        }
    }

    /// Fetch a group by the parent item ID and server.
    public func fetch(itemId: ItemID, serverId: String) async throws -> DownloadGroup? {
        try await dbWriter.read { db in
            let record =
                try DownloadGroupRecord
                .filter(Column("itemId") == itemId.rawValue && Column("serverId") == serverId)
                .fetchOne(db)
            return record?.toDownloadGroup()
        }
    }

    /// Fetch all groups for a server, ordered by creation date (newest first).
    public func fetchAll(serverId: String) async throws -> [DownloadGroup] {
        try await dbWriter.read { db in
            let records =
                try DownloadGroupRecord
                .filter(Column("serverId") == serverId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadGroup() }
        }
    }

    // MARK: - Delete

    /// Delete a group by ID. Child DownloadItems will have their groupId set to NULL (ON DELETE SET NULL).
    public func delete(id: String) async throws {
        try await dbWriter.write { db in
            _ = try DownloadGroupRecord.deleteOne(db, key: id)
        }
        logger.info("Deleted download group: \(id)")
    }

    /// Delete all groups for a server.
    public func deleteAll(serverId: String) async throws {
        let count = try await dbWriter.write { db in
            try DownloadGroupRecord
                .filter(Column("serverId") == serverId)
                .deleteAll(db)
        }
        logger.info("Deleted \(count) download groups for server \(serverId)")
    }
}
