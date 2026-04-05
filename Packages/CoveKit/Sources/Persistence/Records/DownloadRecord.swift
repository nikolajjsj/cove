import Foundation
import GRDB
import Models

/// GRDB record for the `downloads` table.
/// Maps between database rows and the domain `DownloadItem` type.
struct DownloadRecord: Codable, Sendable {
    var id: String
    var itemId: String
    var serverId: String
    var title: String
    var mediaType: String
    var state: String
    var progress: Double
    var totalBytes: Int64
    var downloadedBytes: Int64
    var localFilePath: String?
    var remoteURL: String
    var parentId: String?
    var artworkURL: String?
    var errorMessage: String?
    var createdAt: Date
    var completedAt: Date?

    /// Convert from a domain model.
    init(from item: DownloadItem) {
        self.id = item.id
        self.itemId = item.itemId.rawValue
        self.serverId = item.serverId
        self.title = item.title
        self.mediaType = item.mediaType.rawValue
        self.state = item.state.rawValue
        self.progress = item.progress
        self.totalBytes = item.totalBytes
        self.downloadedBytes = item.downloadedBytes
        self.localFilePath = item.localFilePath
        self.remoteURL = item.remoteURL
        self.parentId = item.parentId?.rawValue
        self.artworkURL = item.artworkURL
        self.errorMessage = item.errorMessage
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
    }

    /// Convert to a domain model.
    /// Returns `nil` if required enum values cannot be decoded.
    func toDownloadItem() -> DownloadItem? {
        guard
            let mediaTypeValue = MediaType(rawValue: mediaType),
            let stateValue = DownloadState(rawValue: state)
        else {
            return nil
        }

        return DownloadItem(
            id: id,
            itemId: ItemID(itemId),
            serverId: serverId,
            title: title,
            mediaType: mediaTypeValue,
            state: stateValue,
            progress: progress,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            localFilePath: localFilePath,
            remoteURL: remoteURL,
            parentId: parentId.map { ItemID($0) },
            artworkURL: artworkURL,
            errorMessage: errorMessage,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }
}

// MARK: - GRDB Conformances

extension DownloadRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "downloads"
}
