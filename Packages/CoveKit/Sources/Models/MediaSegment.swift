import Foundation

/// A skippable segment within a media item (e.g., intro, credits, recap).
///
/// Sourced from Jellyfin 10.9+'s MediaSegments API or the Intro Skipper plugin.
/// Ticks are converted to seconds at the mapping layer.
public struct MediaSegment: Identifiable, Sendable {
    public let id: String
    public let itemId: ItemID
    public let type: MediaSegmentType
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(
        id: String,
        itemId: ItemID,
        type: MediaSegmentType,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.itemId = itemId
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Whether a given playback time falls within this segment.
    public func contains(time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }

    /// Human-readable skip button label.
    public var skipButtonLabel: String {
        switch type {
        case .intro: "Skip Intro"
        case .outro, .credits: "Skip Credits"
        case .recap: "Skip Recap"
        case .preview: "Skip Preview"
        case .commercial: "Skip"
        case .unknown: "Skip"
        }
    }
}

public enum MediaSegmentType: String, Codable, Sendable {
    case unknown = "Unknown"
    case commercial = "Commercial"
    case preview = "Preview"
    case recap = "Recap"
    case outro = "Outro"
    case intro = "Intro"
    case credits = "Credits"
}
