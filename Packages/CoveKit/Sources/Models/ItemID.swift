import Foundation

/// A type-safe identifier for media items, wrapping a String.
public struct ItemID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// Convenience type aliases for domain-specific IDs
public typealias ArtistID = ItemID
public typealias AlbumID = ItemID
public typealias TrackID = ItemID
public typealias SeriesID = ItemID
public typealias SeasonID = ItemID
public typealias PlaylistID = ItemID
public typealias MovieID = ItemID
public typealias EpisodeID = ItemID
