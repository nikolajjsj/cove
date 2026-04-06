import Foundation

/// Describes the source context from which the current playback queue was created.
///
/// Used to display "Playing From *Album Name*" in the queue view and to enable
/// navigation back to the source item when the user taps it.
public struct PlayContext: Sendable, Equatable {
    /// Display title for the source (e.g., "Abbey Road", "Road Trip Mix", "All Songs").
    public let title: String
    /// The type of source that generated this queue.
    public let type: PlayContextType
    /// The ID of the source item, used for navigation. Nil for sources like "All Songs" that don't have a single item.
    public let id: ItemID?

    public init(title: String, type: PlayContextType, id: ItemID? = nil) {
        self.title = title
        self.type = type
        self.id = id
    }
}

/// The type of source that generated a playback queue.
public enum PlayContextType: String, Sendable, Codable {
    case album
    case playlist
    case artist
    case genre
    case songs
    case radio
    case unknown
}
