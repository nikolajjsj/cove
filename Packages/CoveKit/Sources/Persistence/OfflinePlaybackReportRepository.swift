import Foundation
import GRDB
import Models
import os

/// Repository for persisting and querying offline playback reports.
///
/// When the device is offline during media playback, progress events are stored
/// locally via this repository. Once connectivity is restored, unsent reports
/// can be fetched, synced to the server, and marked as synced. Old synced reports
/// can be periodically cleaned up.
public final class OfflinePlaybackReportRepository: Sendable {
    private let dbWriter: any DatabaseWriter
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "Persistence")

    public init(database: DatabaseManager) {
        self.dbWriter = database.dbWriter
    }

    // MARK: - Write Operations

    /// Save an offline playback report (insert or update).
    ///
    /// - Parameter report: The report to persist.
    public func save(_ report: OfflinePlaybackReport) async throws {
        let record = OfflinePlaybackReportRecord(from: report)
        try await dbWriter.write { db in
            try record.save(db)
        }
        logger.debug("Saved offline playback report: \(report.id) (\(report.eventType.rawValue))")
    }

    /// Mark a report as successfully synced to the server.
    ///
    /// - Parameter id: The unique identifier of the report to mark as synced.
    public func markSynced(id: String) async throws {
        try await dbWriter.write { db in
            if var record = try OfflinePlaybackReportRecord.fetchOne(db, key: id) {
                record.isSynced = true
                try record.update(db)
            }
        }
        logger.debug("Marked offline playback report as synced: \(id)")
    }

    /// Delete old synced reports that were created before the given date.
    ///
    /// This is intended for periodic cleanup of reports that have already been
    /// successfully synced to the server and are no longer needed locally.
    ///
    /// - Parameter date: Reports synced and created before this date will be deleted.
    public func deleteOld(before date: Date) async throws {
        try await dbWriter.write { db in
            let count =
                try OfflinePlaybackReportRecord
                .filter(
                    Column("isSynced") == true
                        && Column("timestamp") < date
                )
                .deleteAll(db)
            logger.info("Deleted \(count) old synced playback reports")
        }
    }

    // MARK: - Read Operations

    /// Fetch all reports that have not yet been synced for a given server.
    ///
    /// Results are ordered by timestamp ascending so they can be replayed
    /// to the server in the order they originally occurred.
    ///
    /// - Parameter serverId: The server connection UUID string.
    /// - Returns: An array of unsent reports, ordered by timestamp.
    public func fetchUnsent(serverId: String) async throws -> [OfflinePlaybackReport] {
        try await dbWriter.read { db in
            let records =
                try OfflinePlaybackReportRecord
                .filter(
                    Column("serverId") == serverId
                        && Column("isSynced") == false
                )
                .order(Column("timestamp").asc)
                .fetchAll(db)
            return records.compactMap { $0.toOfflinePlaybackReport() }
        }
    }
}
