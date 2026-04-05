import Foundation

public struct MediaLibrary: Identifiable, Codable, Hashable, Sendable {
    public let id: ItemID
    public let name: String
    public let collectionType: CollectionType?

    public init(id: ItemID, name: String, collectionType: CollectionType? = nil) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

public enum CollectionType: String, Codable, Sendable {
    case movies
    case tvshows
    case music
    case books
    case homevideos
    case boxsets
    case playlists
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CollectionType(rawValue: rawValue) ?? .unknown
    }
}
