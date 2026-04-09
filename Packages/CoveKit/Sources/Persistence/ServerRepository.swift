import Foundation
import GRDB
import Models
import os

/// Repository for persisting and querying server connections.
public final class ServerRepository: Sendable {
    private let dbWriter: any DatabaseWriter
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Persistence")

    public init(database: DatabaseManager) {
        self.dbWriter = database.dbWriter
    }

    /// Save a server connection (insert or update).
    public func save(_ connection: ServerConnection) async throws {
        let record = ServerRecord(from: connection)
        try await dbWriter.write { db in
            try record.save(db)
        }
        logger.info("Saved server connection: \(connection.name)")
    }

    /// Fetch all server connections.
    public func fetchAll() async throws -> [ServerConnection] {
        try await dbWriter.read { db in
            let records = try ServerRecord.fetchAll(db)
            return records.compactMap { $0.toServerConnection() }
        }
    }

    /// Fetch a single server connection by ID.
    public func fetch(id: UUID) async throws -> ServerConnection? {
        try await dbWriter.read { db in
            let record = try ServerRecord.fetchOne(db, key: id.uuidString)
            return record?.toServerConnection()
        }
    }

    /// Delete a server connection by ID.
    public func delete(id: UUID) async throws {
        try await dbWriter.write { db in
            _ = try ServerRecord.deleteOne(db, key: id.uuidString)
        }
        logger.info("Deleted server connection: \(id.uuidString)")
    }

    /// Delete all server connections.
    public func deleteAll() async throws {
        try await dbWriter.write { db in
            _ = try ServerRecord.deleteAll(db)
        }
        logger.info("Deleted all server connections")
    }
}
