import Foundation

/// The preferred audio streaming bitrate for the playback engine.
///
/// Used to request a specific maximum bitrate from the server when
/// transcoding is required. ``lossless`` tells the server not to transcode.
public enum AudioStreamingQuality: String, CaseIterable, Codable, Sendable {
    /// Let the server decide — no bitrate cap requested (effectively 140 Mbps).
    case auto = "auto"
    /// Maximum 128 kbps (suitable for cellular with limited data).
    case low = "low"
    /// Maximum 256 kbps.
    case medium = "medium"
    /// Maximum 320 kbps.
    case high = "high"
    /// Request the original file without transcoding.
    case lossless = "lossless"

    /// Human-readable label for the Settings UI.
    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .low: "Low (128 kbps)"
        case .medium: "Medium (256 kbps)"
        case .high: "High (320 kbps)"
        case .lossless: "Lossless"
        }
    }

    /// The maximum bitrate in bits per second to send to the server, or `nil`
    /// for ``auto`` and ``lossless`` (uses the server's default device profile).
    public var maxBitRate: Int? {
        switch self {
        case .auto: nil
        case .low: 128_000
        case .medium: 256_000
        case .high: 320_000
        case .lossless: nil
        }
    }

    /// Whether the original file should be served without transcoding.
    public var isLossless: Bool { self == .lossless }
}
