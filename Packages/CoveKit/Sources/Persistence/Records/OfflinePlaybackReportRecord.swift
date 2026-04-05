import Foundation
import GRDB
import Models

/// GRDB record for the `offline_playback_reports` table.
/// Maps between database rows and the domain `OfflinePlaybackReport` type.
struct OfflinePlaybackReportRecord: Codable, Sendable {
    var id: String
    var itemId: String
    var serverId: String
    var positionTicks: Int64
    var eventType: String
    var timestamp: Date
    var isSynced: Bool

    /// Convert from a domain model.
    init(from report: OfflinePlaybackReport) {
        self.id = report.id
        self.itemId = report.itemId.rawValue
        self.serverId = report.serverId
        self.positionTicks = report.positionTicks
        self.eventType = report.eventType.rawValue
        self.timestamp = report.timestamp
        self.isSynced = report.isSynced
    }

    /// Convert to a domain model.
    func toOfflinePlaybackReport() -> OfflinePlaybackReport? {
        guard let type = PlaybackEventType(rawValue: eventType) else {
            return nil
        }

        return OfflinePlaybackReport(
            id: id,
            itemId: ItemID(itemId),
            serverId: serverId,
            positionTicks: positionTicks,
            eventType: type,
            timestamp: timestamp,
            isSynced: isSynced
        )
    }
}

// MARK: - GRDB Conformances

extension OfflinePlaybackReportRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "offline_playback_reports"
}
