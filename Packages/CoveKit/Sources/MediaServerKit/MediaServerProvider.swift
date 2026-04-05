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

    // Images
    func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL?

    // Search
    func search(query: String, mediaTypes: [MediaType]) async throws -> SearchResults
}
