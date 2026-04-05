import Foundation

/// Represents a selectable subtitle track for video playback.
public struct SubtitleTrack: Identifiable, Sendable {
    public let id: Int  // stream index
    public let title: String
    public let language: String?
    public let isExternal: Bool
    public let url: URL?  // non-nil for external subtitle tracks (VTT/SRT)

    public init(
        id: Int, title: String, language: String? = nil, isExternal: Bool = false, url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.isExternal = isExternal
        self.url = url
    }
}
