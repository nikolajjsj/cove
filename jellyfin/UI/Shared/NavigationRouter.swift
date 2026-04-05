import Models
import SwiftUI

/// Centralized navigation routing for media items.
/// Keeps the mapping from `MediaItem.mediaType` → detail view in one place.
enum NavigationRouter {

    /// Returns the appropriate detail view for a given media item.
    @ViewBuilder
    static func destination(for item: MediaItem) -> some View {
        switch item.mediaType {
        case .movie, .episode:
            MovieDetailView(item: item)
        case .series:
            SeriesDetailView(item: item)
        case .artist:
            ArtistDetailView(artistItem: item)
        case .album:
            AlbumDetailView(albumItem: item)
        default:
            Text(item.title)
                .navigationTitle(item.title)
        }
    }
}

// MARK: - Library Type Helpers

extension MediaLibrary {
    /// Returns the Jellyfin `IncludeItemTypes` values appropriate for this library's collection type.
    /// This ensures TV Shows libraries return only Series (not Seasons/Episodes),
    /// Movies libraries return only Movies, etc.
    var includeItemTypes: [String]? {
        switch collectionType {
        case .movies:
            return ["Movie"]
        case .tvshows:
            return ["Series"]
        default:
            return nil
        }
    }
}
