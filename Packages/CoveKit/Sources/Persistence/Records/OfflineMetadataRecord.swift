import Foundation
import GRDB
import Models

/// GRDB record for the `offline_metadata` table.
/// Maps between database rows and the domain `OfflineMediaMetadata` type.
///
/// The full metadata model is serialized as a JSON blob in the `metadataJSON` column,
/// while key fields are stored as top-level columns for efficient querying.
struct OfflineMetadataRecord: Codable, Sendable {
    var itemId: String
    var serverId: String
    var mediaType: String
    var metadataJSON: Data
    var updatedAt: Date

    /// Convert from a domain model by encoding the full metadata as JSON.
    init(from metadata: OfflineMediaMetadata) {
        self.itemId = metadata.itemId
        self.serverId = metadata.serverId
        self.mediaType = metadata.mediaType

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Force-try is acceptable here: OfflineMediaMetadata is always encodable.
        // swiftlint:disable:next force_try
        self.metadataJSON = try! encoder.encode(metadata)

        self.updatedAt = Date()
    }

    /// Convert back to the domain model by decoding the JSON blob.
    /// Returns `nil` if the stored JSON is corrupt or incompatible.
    func toOfflineMediaMetadata() -> OfflineMediaMetadata? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OfflineMediaMetadata.self, from: metadataJSON)
    }
}

// MARK: - GRDB Conformances

extension OfflineMetadataRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "offline_metadata"
}
