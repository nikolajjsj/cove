import Foundation
import Models
import Persistence
import os

/// Manages offline playback report queuing and synchronisation.
///
/// When the device is offline during media playback, events (start, progress, stopped)
/// are queued locally via ``queuePlaybackEvent(itemId:serverId:positionTicks:eventType:)``.
/// Once connectivity is restored the caller invokes
/// ``syncPendingReports(serverId:sender:)`` with a closure that actually POSTs each
/// report to the Jellyfin server. Successfully-synced reports are marked in the
/// database and periodically cleaned up by ``cleanup()``.
public final class OfflineSyncManager: Sendable {

    // MARK: - Dependencies

    private let reportRepository: OfflinePlaybackReportRepository
    private let logger = Logger(
        subsystem: "com.nikolajjsj.jellyfin", category: "OfflineSyncManager")

    /// How long synced reports are kept before `cleanup()` deletes them.
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // MARK: - Init

    /// Creates a new sync manager backed by the given report repository.
    ///
    /// - Parameter reportRepository: The persistence layer for offline playback reports.
    public init(reportRepository: OfflinePlaybackReportRepository) {
        self.reportRepository = reportRepository
    }

    // MARK: - Queuing

    /// Queue a playback event for later synchronisation.
    ///
    /// Call this whenever a playback event occurs and the device may be offline
    /// (or unconditionally — the sync step is idempotent).
    ///
    /// - Parameters:
    ///   - itemId: The media item being played.
    ///   - serverId: The server the item belongs to.
    ///   - positionTicks: Current playback position in ticks (1 tick = 100 ns).
    ///   - eventType: The kind of playback event (`.start`, `.progress`, `.stopped`).
    public func queuePlaybackEvent(
        itemId: ItemID,
        serverId: String,
        positionTicks: Int64,
        eventType: PlaybackEventType
    ) async throws {
        let report = OfflinePlaybackReport(
            id: UUID().uuidString,
            itemId: itemId,
            serverId: serverId,
            positionTicks: positionTicks,
            eventType: eventType,
            timestamp: Date(),
            isSynced: false
        )

        try await reportRepository.save(report)
        logger.info(
            "Queued \(eventType.rawValue) event for item \(itemId.rawValue) on server \(serverId)"
        )
    }

    // MARK: - Synchronisation

    /// Attempt to sync all pending (unsent) reports for a server.
    ///
    /// Each report is passed to `sender` which should POST it to the Jellyfin
    /// server. If `sender` succeeds the report is marked as synced; if it throws
    /// the report is left as-is for a future retry.
    ///
    /// - Parameters:
    ///   - serverId: The server whose pending reports should be synced.
    ///   - sender: An async closure that transmits a single report to the server.
    ///             Throwing indicates the report could not be delivered and should
    ///             be retried later.
    public func syncPendingReports(
        serverId: String,
        sender: @Sendable (OfflinePlaybackReport) async throws -> Void
    ) async {
        let reports: [OfflinePlaybackReport]
        do {
            reports = try await reportRepository.fetchUnsent(serverId: serverId)
        } catch {
            logger.error(
                "Failed to fetch unsent reports for server \(serverId): \(error.localizedDescription)"
            )
            return
        }

        guard !reports.isEmpty else {
            logger.debug("No pending reports to sync for server \(serverId)")
            return
        }

        logger.info("Syncing \(reports.count) pending report(s) for server \(serverId)")

        var syncedCount = 0
        var failedCount = 0

        for report in reports {
            do {
                try await sender(report)
                try await reportRepository.markSynced(id: report.id)
                syncedCount += 1
                logger.debug(
                    "Synced report \(report.id) (\(report.eventType.rawValue) for \(report.itemId.rawValue))"
                )
            } catch {
                failedCount += 1
                logger.warning(
                    "Failed to sync report \(report.id): \(error.localizedDescription) — will retry later"
                )
                // Continue with the remaining reports instead of aborting the whole batch.
                // However, if we're getting consistent failures it's likely a network issue,
                // so bail after 3 consecutive failures to avoid burning battery.
                if failedCount >= 3 {
                    logger.warning(
                        "Aborting sync after \(failedCount) consecutive failures for server \(serverId)"
                    )
                    break
                }
            }
        }

        logger.info(
            "Sync complete for server \(serverId): \(syncedCount) synced, \(failedCount) failed out of \(reports.count)"
        )
    }

    // MARK: - Cleanup

    /// Delete old synced reports that are older than the retention window (7 days).
    ///
    /// Call this periodically (e.g. on app launch or when a sync completes) to
    /// prevent the local database from growing indefinitely.
    public func cleanup() async {
        let cutoff = Date(timeIntervalSinceNow: -retentionInterval)
        do {
            try await reportRepository.deleteOld(before: cutoff)
            logger.info("Cleaned up synced reports older than 7 days")
        } catch {
            logger.error("Failed to clean up old reports: \(error.localizedDescription)")
        }
    }
}
