import MediaServerKit
import Models
import SwiftUI

// MARK: - Music Browse Routes

/// Routes for "See All" navigation from the music library shelves.
/// Registered in the centralized `NavigationDestinations` modifier so
/// all navigation goes through `NavigationLink(value:)` — no inline destinations.
enum MusicBrowseRoute: Hashable {
    case allArtists(libraryId: ItemID)
    case allAlbums(libraryId: ItemID)
}

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
        case .genre:
            GenreDetailView(genreItem: item, library: nil)
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

    /// Returns the detail view for a given playlist.
    @ViewBuilder
    static func destination(for playlist: Playlist) -> some View {
        PlaylistDetailView(playlist: playlist)
    }

    /// Returns the detail view for a given person.
    @ViewBuilder
    static func destination(for person: Person) -> some View {
        PersonDetailView(person: person)
    }

    /// Returns the browsing view for a music "See All" route.
    @ViewBuilder
    static func destination(for route: MusicBrowseRoute, appState: AppState) -> some View {
        let library = appState.libraries.first { $0.collectionType == .music }
        switch route {
        case .allArtists:
            ArtistListView(library: library)
                .navigationTitle("Artists")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.large)
                #endif
        case .allAlbums:
            AlbumListView(library: library)
                .navigationTitle("Albums")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.large)
                #endif
        }
    }
}

// MARK: - Navigation Destinations Modifier

private struct NavigationDestinations: ViewModifier {
    @Environment(AppState.self) private var appState

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
            .navigationDestination(for: Playlist.self) { playlist in
                NavigationRouter.destination(for: playlist)
            }
            .navigationDestination(for: Person.self) { person in
                NavigationRouter.destination(for: person)
            }
            .navigationDestination(for: MusicBrowseRoute.self) { route in
                NavigationRouter.destination(for: route, appState: appState)
            }
            .navigationDestination(for: SearchSeeAllRoute.self) { route in
                SearchSeeAllView(
                    query: route.query,
                    mediaType: route.mediaType,
                    title: route.title
                )
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
