import Foundation

/// Describes how a media item is being played back.
public enum PlayMethod: String, Codable, Sendable {
    /// The file is streamed as-is — container and codecs are natively supported.
    case directPlay = "DirectPlay"
    /// The server remuxes the container on-the-fly (e.g. MKV → MP4) without re-encoding.
    case directStream = "DirectStream"
    /// The server fully transcodes the media (re-encodes video and/or audio).
    case transcode = "Transcode"
}
