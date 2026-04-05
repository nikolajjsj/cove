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
        case .collection:
            CollectionDetailView(item: item)
        case .artist:
            ArtistDetailView(artistItem: item)
        case .album:
            AlbumDetailView(albumItem: item)
        default:
            Text(item.title)
                .navigationTitle(item.title)
        }
    }

    /// Returns the appropriate detail view for a given media library.
    @ViewBuilder
    static func destination(for library: MediaLibrary) -> some View {
        switch library.collectionType {
        case .music:
            MusicLibraryView(library: library)
        default:
            LibraryGridView(library: library)
        }
    }

    /// Returns the detail view for a given album.
    @ViewBuilder
    static func destination(for album: Album) -> some View {
        AlbumDetailView(albumItem: MediaItem(id: album.id, title: album.title, mediaType: .album))
    }
}

// MARK: - Navigation Destinations Modifier

private struct NavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: MediaItem.self) { item in
                NavigationRouter.destination(for: item)
            }
            .navigationDestination(for: MediaLibrary.self) { library in
                NavigationRouter.destination(for: library)
            }
            .navigationDestination(for: Album.self) { album in
                NavigationRouter.destination(for: album)
            }
    }
}

extension View {
    func withNavigationDestinations() -> some View {
        modifier(NavigationDestinations())
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
        case .boxsets:
            return ["BoxSet"]
        default:
            return nil
        }
    }
}
