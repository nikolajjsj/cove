import Foundation

/// A chapter marker within a media item.
///
/// Chapters are authored into media files or added by Jellyfin plugins.
/// They provide named navigation points (e.g., "Opening Credits", "Act 1").
public struct Chapter: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let startPosition: TimeInterval
    public let imageTag: String?

    public init(
        id: Int,
        name: String,
        startPosition: TimeInterval,
        imageTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startPosition = startPosition
        self.imageTag = imageTag
    }
}
