import DownloadManager
import Models
import SwiftUI

/// The tabs/sidebar sections available in the app shell.
/// Defined at the app level so it can be referenced from `AppState` for navigation.
enum AppTab: Hashable {
    case home
    case search
    case music
    case movies
    case tvShows
    case downloads
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .music: "Music"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .music: "music.note"
        case .movies: "film"
        case .tvShows: "tv"
        case .downloads: "arrow.down.circle"
        case .settings: "gear"
        }
    }

    @ViewBuilder
    func destination(appState: AppState, downloadCoordinator: DownloadCoordinator) -> some View {
        switch self {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .music:
            MusicLibraryView(library: appState.libraries.first { $0.collectionType == .music })
        case .movies:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .movies })
        case .tvShows:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .tvshows })
        case .downloads:
            if let downloadManager = downloadCoordinator.downloadManager {
                DownloadsView(downloadManager: downloadManager)
            } else {
                ContentUnavailableView(
                    "Downloads Unavailable",
                    systemImage: "arrow.down.circle.dotted",
                    description: Text(
                        "Download functionality requires local storage to be available.")
                )
            }
        case .settings:
            SettingsView()
        }
    }
}
