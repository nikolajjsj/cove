import Foundation
import GRDB
import Models

/// A row of `catalog_items`. See `CatalogEntry` for what the columns mean.
public struct CatalogItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "catalog_items"

    public var serverId: String
    public var userId: String
    public var itemId: String
    public var libraryId: String
    public var parentId: String?
    public var seriesId: String?
    public var seasonId: String?
    public var type: String
    public var mediaType: String
    public var name: String
    public var sortName: String
    public var productionYear: Int?
    public var premiereDate: Date?
    public var dateCreated: Date
    public var runTimeTicks: Int64?
    public var communityRating: Double?
    public var criticRating: Double?
    public var officialRating: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var seriesName: String?
    public var imageTags: String?
    public var lastSeenInReconcile: Date?

    public init(entry: CatalogEntry, serverId: String, userId: String) {
        self.serverId = serverId
        self.userId = userId
        self.itemId = entry.id
        self.libraryId = entry.libraryId
        self.parentId = entry.parentId
        self.seriesId = entry.seriesId
        self.seasonId = entry.seasonId
        self.type = entry.type
        self.mediaType = entry.mediaType.rawValue
        self.name = entry.name
        self.sortName = entry.sortName
        self.productionYear = entry.productionYear
        self.premiereDate = entry.premiereDate
        self.dateCreated = entry.dateCreated
        self.runTimeTicks = entry.runTimeTicks
        self.communityRating = entry.communityRating
        self.criticRating = entry.criticRating
        self.officialRating = entry.officialRating
        self.indexNumber = entry.indexNumber
        self.parentIndexNumber = entry.parentIndexNumber
        self.seriesName = entry.seriesName
        self.imageTags = Self.encodeImageTags(entry.imageTags)
        self.lastSeenInReconcile = nil
    }

    // Upserting must not clobber the reconcile stamp; the conflict clause below
    // lists exactly the columns a sync page is allowed to overwrite.
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .abort, update: .abort)

    /// Column names a catalogue page may overwrite on conflict.
    static let syncedColumns: [String] = [
        "libraryId", "parentId", "seriesId", "seasonId", "type", "mediaType", "name",
        "sortName", "productionYear", "premiereDate", "dateCreated", "runTimeTicks",
        "communityRating", "criticRating", "officialRating", "indexNumber",
        "parentIndexNumber", "seriesName", "imageTags",
    ]

    static func encodeImageTags(_ tags: [ImageType: String]?) -> String? {
        guard let tags, !tags.isEmpty else { return nil }
        let raw = Dictionary(uniqueKeysWithValues: tags.map { ($0.key.rawValue, $0.value) })
        return (try? JSONEncoder().encode(raw)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decodeImageTags(_ json: String?) -> [ImageType: String]? {
        guard let json, let data = json.data(using: .utf8),
            let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        var out: [ImageType: String] = [:]
        for (key, value) in raw {
            if let type = ImageType(rawValue: key) { out[type] = value }
        }
        return out.isEmpty ? nil : out
    }
}

/// A row of `catalog_user_data`.
public struct CatalogUserDataRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "catalog_user_data"

    public var serverId: String
    public var userId: String
    public var itemId: String
    public var played: Bool
    public var playCount: Int
    public var isFavorite: Bool
    public var playbackPositionTicks: Int64
    public var lastPlayedDate: Date?

    public init(userData: UserData, serverId: String, userId: String, itemId: String) {
        self.serverId = serverId
        self.userId = userId
        self.itemId = itemId
        self.played = userData.isPlayed
        self.playCount = userData.playCount
        self.isFavorite = userData.isFavorite
        self.playbackPositionTicks = Int64(userData.playbackPosition * 10_000_000)
        self.lastPlayedDate = userData.lastPlayedDate
    }

    public var asUserData: UserData {
        UserData(
            isFavorite: isFavorite,
            playbackPosition: TimeInterval(playbackPositionTicks) / 10_000_000,
            playCount: playCount,
            isPlayed: played,
            lastPlayedDate: lastPlayedDate)
    }
}

public struct CatalogItemGenreRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "catalog_item_genres"
    public var serverId: String
    public var userId: String
    public var itemId: String
    public var genreId: String
    public var genreName: String
}

public struct CatalogItemStudioRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "catalog_item_studios"
    public var serverId: String
    public var userId: String
    public var itemId: String
    public var studioName: String
}

/// A row of `sync_state`: one per (server, user, scope).
public struct SyncStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sync_state"

    public var serverId: String
    public var userId: String
    public var scope: String
    public var cursor: Date?
    public var bootstrapNextIndex: Int
    public var bootstrapComplete: Bool
    public var lastRunAt: Date?
    public var lastError: String?

    public init(serverId: String, userId: String, scope: String) {
        self.serverId = serverId
        self.userId = userId
        self.scope = scope
        self.cursor = nil
        self.bootstrapNextIndex = 0
        self.bootstrapComplete = false
        self.lastRunAt = nil
        self.lastError = nil
    }
}

/// A row of `user_data_outbox`. Written in Phase 4; the table exists from 004 so
/// the schema does not need a second migration.
public struct UserDataOutboxRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "user_data_outbox"

    public var id: String
    public var serverId: String
    public var userId: String
    public var itemId: String
    public var field: String
    public var value: String
    public var occurredAt: Date
    public var attempts: Int
    public var lastAttemptAt: Date?
    public var lastError: String?
}

/// A row of `catalog_libraries`: the user's views, so Home has something to
/// show when the server cannot be reached.
public struct CatalogLibraryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "catalog_libraries"
    public var serverId: String
    public var userId: String
    public var libraryId: String
    public var name: String
    public var collectionType: String?
    public var sortIndex: Int

    public var asLibrary: MediaLibrary {
        MediaLibrary(
            id: ItemID(libraryId), name: name,
            collectionType: collectionType.flatMap(CollectionType.init(rawValue:)))
    }
}
