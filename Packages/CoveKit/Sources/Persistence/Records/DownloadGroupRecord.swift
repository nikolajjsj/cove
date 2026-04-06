import Foundation
import GRDB
import Models

/// GRDB record for the `download_groups` table.
/// Maps between database rows and the domain `DownloadGroup` type.
struct DownloadGroupRecord: Codable, Sendable {
    var id: String
    var itemId: String
    var serverId: String
    var mediaType: String
    var title: String
    var createdAt: Date

    /// Convert from a domain model.
    init(from group: DownloadGroup) {
        self.id = group.id
        self.itemId = group.itemId.rawValue
        self.serverId = group.serverId
        self.mediaType = group.mediaType.rawValue
        self.title = group.title
        self.createdAt = group.createdAt
    }

    /// Convert to a domain model.
    /// Returns `nil` if required enum values cannot be decoded.
    func toDownloadGroup() -> DownloadGroup? {
        guard let mediaTypeValue = MediaType(rawValue: mediaType) else {
            return nil
        }

        return DownloadGroup(
            id: id,
            itemId: ItemID(itemId),
            serverId: serverId,
            mediaType: mediaTypeValue,
            title: title,
            createdAt: createdAt
        )
    }
}

// MARK: - GRDB Conformances

extension DownloadGroupRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "download_groups"
}
