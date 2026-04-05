import Foundation

public struct SearchResults: Sendable {
    public let items: [MediaItem]

    public init(items: [MediaItem] = []) {
        self.items = items
    }

    /// Filter results by media type
    public func items(ofType type: MediaType) -> [MediaItem] {
        items.filter { $0.mediaType == type }
    }
}
