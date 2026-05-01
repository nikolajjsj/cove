import Foundation
import GRDB
import Models
import os

/// Repository for persisting and querying offline media metadata.
///
/// Provides CRUD operations for managing cached metadata of offline-available
/// media items. Metadata is stored as a JSON blob alongside indexed lookup columns.
/// All methods are async and safe to call from any concurrency context.
public final class OfflineMetadataRepository: Sendable {
    private let dbWriter: any DatabaseWriter
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Persistence")

    public init(database: DatabaseManager) {
        self.dbWriter = database.dbWriter
    }

    // MARK: - Save

    /// Save or update offline metadata for an item.
    public func save(_ metadata: OfflineMediaMetadata) async throws {
        let record = try OfflineMetadataRecord(from: metadata)
        try await dbWriter.write { db in
            // Use INSERT OR REPLACE since composite PK (itemId, serverId)
            try record.save(db)
        }
        logger.info("Saved offline metadata for item \(metadata.itemId)")
    }

    // MARK: - Fetch

    /// Fetch metadata for a specific item on a specific server.
    public func fetch(itemId: String, serverId: String) async throws -> OfflineMediaMetadata? {
        try await dbWriter.read { db in
            let record =
                try OfflineMetadataRecord
                .filter(Column("itemId") == itemId && Column("serverId") == serverId)
                .fetchOne(db)
            return record?.toOfflineMediaMetadata()
        }
    }

    /// Fetch all metadata for a server, optionally filtered by media type.
    public func fetchAll(serverId: String, mediaType: String? = nil) async throws
        -> [OfflineMediaMetadata]
    {
        try await dbWriter.read { db in
            var request = OfflineMetadataRecord.filter(Column("serverId") == serverId)
            if let mediaType {
                request = request.filter(Column("mediaType") == mediaType)
            }
            let records = try request.order(Column("updatedAt").desc).fetchAll(db)
            return records.compactMap { $0.toOfflineMediaMetadata() }
        }
    }

    // MARK: - Delete

    /// Delete metadata for a specific item.
    public func delete(itemId: String, serverId: String) async throws {
        try await dbWriter.write { db in
            _ =
                try OfflineMetadataRecord
                .filter(Column("itemId") == itemId && Column("serverId") == serverId)
                .deleteAll(db)
        }
        logger.info("Deleted offline metadata for item \(itemId)")
    }

    /// Delete all metadata for a server.
    public func deleteAll(serverId: String) async throws {
        let count = try await dbWriter.write { db in
            try OfflineMetadataRecord
                .filter(Column("serverId") == serverId)
                .deleteAll(db)
        }
        logger.info("Deleted \(count) offline metadata records for server \(serverId)")
    }
}
