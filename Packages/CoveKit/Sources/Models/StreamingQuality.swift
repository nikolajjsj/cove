import Foundation

/// Predefined streaming quality tiers for video playback.
///
/// Each tier maps to a `maxStreamingBitrate` value sent to the server.
/// "Auto" uses the default device profile (120 Mbps — effectively always direct play).
/// "Original" forces direct play regardless of codec compatibility.
public enum StreamingQuality: String, Codable, Hashable, CaseIterable, Sendable {
    case auto
    case original
    case quality1080p = "1080p"
    case quality720p = "720p"
    case quality480p = "480p"

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .original: "Original"
        case .quality1080p: "1080p (10 Mbps)"
        case .quality720p: "720p (4 Mbps)"
        case .quality480p: "480p (2 Mbps)"
        }
    }

    /// The maximum streaming bitrate in bits per second for this tier.
    /// Returns `nil` for `.auto` and `.original` (use default profile).
    public var maxBitrate: Int? {
        switch self {
        case .auto: nil
        case .original: nil
        case .quality1080p: 10_000_000
        case .quality720p: 4_000_000
        case .quality480p: 2_000_000
        }
    }

    /// Maximum video width for this tier. Used in codec profile conditions.
    /// Returns `nil` for `.auto` and `.original`.
    public var maxWidth: Int? {
        switch self {
        case .auto: nil
        case .original: nil
        case .quality1080p: 1920
        case .quality720p: 1280
        case .quality480p: 854
        }
    }
}
