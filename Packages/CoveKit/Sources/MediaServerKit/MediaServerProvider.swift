import Foundation
import Models

/// Base protocol that every media server backend must implement.
public protocol MediaServerProvider: Sendable {
    // Connection
    func connect(url: URL, credentials: Credentials) async throws -> ServerConnection
    func disconnect() async

    // Library browsing
    func libraries() async throws -> [MediaLibrary]
    func items(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions) async throws
        -> [MediaItem]

    /// Paginated library browsing — returns items with total count for infinite scroll.
    func pagedItems(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions) async throws
        -> PagedResult<MediaItem>

    func item(id: ItemID) async throws -> MediaItem

    // Similar items
    func similarItems(for item: MediaItem, limit: Int?) async throws -> [MediaItem]

    // Person filmography
    func personItems(personId: ItemID) async throws -> [MediaItem]

    // Images
    func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL?

    // Search
    func search(query: String, mediaTypes: [MediaType]) async throws -> SearchResults
    func searchPaged(query: String, includeItemTypes: [String]?, limit: Int?, startIndex: Int?)
        async throws -> PagedResult<MediaItem>
}

extension MediaServerProvider {
    /// Convenience overload that resolves an image URL by item ID alone,
    /// avoiding the need to construct a full `MediaItem` just for image lookups.
    public func imageURL(for itemId: ItemID, type: ImageType, maxSize: CGSize?) -> URL? {
        let placeholder = MediaItem(id: itemId, title: "", mediaType: .movie)
        return imageURL(for: placeholder, type: type, maxSize: maxSize)
    }
}
