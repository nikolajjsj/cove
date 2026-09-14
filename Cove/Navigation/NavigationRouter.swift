import MediaServerKit
import Models
import SwiftUI

/// Centralized navigation routing for media items.
/// Keeps the mapping from `MediaItem.mediaType` → detail view in one place.
enum NavigationRouter {

    /// Returns the appropriate detail view for a given media item.
    @ViewBuilder
    static func destination(for item: MediaItem) -> some View {
        switch item.mediaType {
        case .movie:
            MovieDetailView(item: item)
        case .episode:
            EpisodeDetailView(item: item)
        case .series:
            SeriesDetailView(item: item)
        case .collection:
            CollectionDetailView(item: item)
        case .genre:
            VideoGenreDetailView(genreName: item.title, library: nil)
        case .studio:
            Text(item.title)
                .navigationTitle(item.title)
        default:
            Text(item.title)
                .navigationTitle(item.title)
        }
    }

    /// Returns the appropriate detail view for a given media library.
    @ViewBuilder
    static func destination(for library: MediaLibrary) -> some View {
        LibraryGridView(library: library)
    }

    /// Returns the detail view for a given person.
    @ViewBuilder
    static func destination(for person: Person) -> some View {
        PersonDetailView(person: person)
    }

    /// Returns the detail view for a video genre route.
    @ViewBuilder
    static func destination(for route: VideoGenreRoute, appState: AppState) -> some View {
        let library = appState.libraries.first { $0.id == route.libraryId }
        VideoGenreDetailView(genreName: route.genre, library: library)
    }

    /// Returns the detail view for a video studio route.
    @ViewBuilder
    static func destination(for route: StudioRoute, appState: AppState) -> some View {
        let library =
            appState.libraries.first { $0.id == route.libraryId }
            ?? appState.libraries.first {
                $0.collectionType == .movies || $0.collectionType == .tvshows
            }
        StudioDetailView(studioName: route.studio, library: library)
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
            .navigationDestination(for: Person.self) { person in
                NavigationRouter.destination(for: person)
            }
            .navigationDestination(for: VideoGenreRoute.self) { route in
                NavigationRouter.destination(for: route, appState: appState)
            }
            .navigationDestination(for: StudioRoute.self) { route in
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
