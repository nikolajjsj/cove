import Foundation

/// Represents a selectable audio track for video playback.
public struct AudioTrack: Identifiable, Sendable {
    public let id: Int  // index into the AVMediaSelectionGroup options
    public let title: String
    public let language: String?
    public let codec: String?
    public let channels: Int?
    public let isDefault: Bool

    public init(
        id: Int,
        title: String,
        language: String? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.channels = channels
        self.isDefault = isDefault
    }
}
