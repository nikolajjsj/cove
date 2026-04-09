import Foundation
import GRDB
import Models
import os

/// Repository for persisting and querying download items.
///
/// Provides full CRUD operations for managing the download lifecycle,
/// including state transitions, progress tracking, and storage queries.
/// All methods are async and safe to call from any concurrency context.
public final class DownloadRepository: Sendable {
    private let dbWriter: any DatabaseWriter
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Persistence")

    public init(database: DatabaseManager) {
        self.dbWriter = database.dbWriter
    }

    // MARK: - Save

    /// Save a download item (insert or update).
    public func save(_ item: DownloadItem) async throws {
        let record = DownloadRecord(from: item)
        try await dbWriter.write { db in
            try record.save(db)
        }
        logger.info("Saved download: \(item.title) [\(item.id)]")
    }

    // MARK: - Fetch

    /// Fetch all downloads, ordered by creation date (newest first).
    public func fetchAll() async throws -> [DownloadItem] {
        try await dbWriter.read { db in
            let records =
                try DownloadRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadItem() }
        }
    }

    /// Fetch all downloads for a specific server, ordered by creation date (newest first).
    public func fetchAll(serverId: String) async throws -> [DownloadItem] {
        try await dbWriter.read { db in
            let records =
                try DownloadRecord
                .filter(Column("serverId") == serverId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadItem() }
        }
    }

    /// Fetch all downloads in a given state, ordered by creation date (oldest first).
    public func fetchAll(state: DownloadState) async throws -> [DownloadItem] {
        try await dbWriter.read { db in
            let records =
                try DownloadRecord
                .filter(Column("state") == state.rawValue)
                .order(Column("createdAt").asc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadItem() }
        }
    }

    /// Fetch all downloads belonging to a specific group, ordered by creation date (oldest first).
    public func fetchAll(groupId: String) async throws -> [DownloadItem] {
        try await dbWriter.read { db in
            let records =
                try DownloadRecord
                .filter(Column("groupId") == groupId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadItem() }
        }
    }

    /// Fetch a single download by its unique ID.
    public func fetch(id: String) async throws -> DownloadItem? {
        try await dbWriter.read { db in
            let record = try DownloadRecord.fetchOne(db, key: id)
            return record?.toDownloadItem()
        }
    }

    /// Fetch a download by media item ID and server ID.
    ///
    /// This is useful for checking whether a particular media item has already
    /// been downloaded or is in the download queue for a given server.
    public func fetch(itemId: ItemID, serverId: String) async throws -> DownloadItem? {
        try await dbWriter.read { db in
            let record =
                try DownloadRecord
                .filter(Column("itemId") == itemId.rawValue)
                .filter(Column("serverId") == serverId)
                .fetchOne(db)
            return record?.toDownloadItem()
        }
    }

    /// Fetch only completed downloads for a server, ordered by completion date (newest first).
    public func downloadedItems(serverId: String) async throws -> [DownloadItem] {
        try await dbWriter.read { db in
            let records =
                try DownloadRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("state") == DownloadState.completed.rawValue)
                .order(Column("completedAt").desc)
                .fetchAll(db)
            return records.compactMap { $0.toDownloadItem() }
        }
    }

    // MARK: - Delete

    /// Delete a single download by ID.
    public func delete(id: String) async throws {
        try await dbWriter.write { db in
            _ = try DownloadRecord.deleteOne(db, key: id)
        }
        logger.info("Deleted download: \(id)")
    }

    /// Delete all downloads for a specific server.
    public func deleteAll(serverId: String) async throws {
        let count = try await dbWriter.write { db in
            try DownloadRecord
                .filter(Column("serverId") == serverId)
                .deleteAll(db)
        }
        logger.info("Deleted \(count) downloads for server: \(serverId)")
    }

    // MARK: - State Updates

    /// Update the state of a download, optionally setting an error message.
    ///
    /// - Parameters:
    ///   - id: The download's unique identifier.
    ///   - state: The new download state.
    ///   - errorMessage: An optional error message (typically set when state is `.failed`).
    public func updateState(id: String, state: DownloadState, errorMessage: String? = nil)
        async throws
    {
        try await dbWriter.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.state = state.rawValue
                record.errorMessage = errorMessage
                try record.update(db)
            }
        }
        logger.info("Updated download \(id) state to \(state.rawValue)")
    }

    /// Update the byte-level progress of a download.
    ///
    /// - Parameters:
    ///   - id: The download's unique identifier.
    ///   - downloadedBytes: The number of bytes downloaded so far.
    ///   - progress: The fractional progress from 0.0 to 1.0.
    public func updateProgress(id: String, downloadedBytes: Int64, progress: Double) async throws {
        try await dbWriter.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.downloadedBytes = downloadedBytes
                record.progress = progress
                try record.update(db)
            }
        }
    }

    /// Mark a download as completed with the local file path.
    ///
    /// Sets the state to `.completed`, progress to 1.0, and records the completion timestamp.
    ///
    /// - Parameters:
    ///   - id: The download's unique identifier.
    ///   - localFilePath: The relative path to the downloaded file under the downloads directory.
    public func markCompleted(id: String, localFilePath: String) async throws {
        try await dbWriter.write { db in
            if var record = try DownloadRecord.fetchOne(db, key: id) {
                record.state = DownloadState.completed.rawValue
                record.localFilePath = localFilePath
                record.progress = 1.0
                record.completedAt = Date()
                record.errorMessage = nil
                try record.update(db)
            }
        }
        logger.info("Marked download \(id) as completed at path: \(localFilePath)")
    }

    // MARK: - Aggregates

    /// Calculate the total bytes stored on disk for completed downloads belonging to a server.
    ///
    /// - Parameter serverId: The server connection UUID string.
    /// - Returns: Total downloaded bytes across all completed downloads for the server.
    public func totalDownloadedBytes(serverId: String) async throws -> Int64 {
        try await dbWriter.read { db in
            let request =
                DownloadRecord
                .filter(Column("serverId") == serverId)
                .filter(Column("state") == DownloadState.completed.rawValue)
                .select(sum(Column("downloadedBytes")))
            return try Int64.fetchOne(db, request) ?? 0
        }
    }

    // MARK: - Observation

    /// Observe all downloads for a server, emitting updates whenever the data changes.
    /// Uses GRDB's `ValueObservation` for real-time database observation.
    public func observeAll(serverId: String) -> AsyncStream<[DownloadItem]> {
        let observation = ValueObservation.tracking { db in
            try DownloadRecord
                .filter(Column("serverId") == serverId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: dbWriter,
                onError: { error in
                    // On error, don't finish the stream — just skip this update
                },
                onChange: { records in
                    let items = records.compactMap { $0.toDownloadItem() }
                    continuation.yield(items)
                }
            )

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    /// Observe only active downloads (downloading, queued, paused) and failed downloads.
    public func observeActive(serverId: String) -> AsyncStream<[DownloadItem]> {
        let activeStates = [
            DownloadState.downloading.rawValue,
            DownloadState.queued.rawValue,
            DownloadState.paused.rawValue,
            DownloadState.failed.rawValue,
        ]

        let observation = ValueObservation.tracking { db in
            try DownloadRecord
                .filter(Column("serverId") == serverId)
                .filter(activeStates.contains(Column("state")))
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: dbWriter,
                onError: { _ in },
                onChange: { records in
                    let items = records.compactMap { $0.toDownloadItem() }
                    continuation.yield(items)
                }
            )

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    /// Observe a single download by item ID and server ID.
    public func observeOne(itemId: ItemID, serverId: String) -> AsyncStream<DownloadItem?> {
        let observation = ValueObservation.tracking { db in
            try DownloadRecord
                .filter(Column("itemId") == itemId.rawValue)
                .filter(Column("serverId") == serverId)
                .fetchOne(db)
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: dbWriter,
                onError: { _ in },
                onChange: { record in
                    continuation.yield(record?.toDownloadItem())
                }
            )

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    /// Observe all downloads belonging to a specific group.
    public func observeGroup(groupId: String) -> AsyncStream<[DownloadItem]> {
        let observation = ValueObservation.tracking { db in
            try DownloadRecord
                .filter(Column("groupId") == groupId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: dbWriter,
                onError: { _ in },
                onChange: { records in
                    let items = records.compactMap { $0.toDownloadItem() }
                    continuation.yield(items)
                }
            )

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
