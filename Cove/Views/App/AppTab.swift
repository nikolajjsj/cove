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

    // MARK: - Shell Layout

    /// Describes the navigation layout context for tab selection.
    enum ShellLayout {
        /// iPhone bottom tab bar — limited tab count.
        case compact
        /// iPad sidebar or Mac sidebar — all tabs shown.
        case regular
        /// tvOS top tab bar — no downloads, all media tabs.
        case tv
    }

    /// Returns the appropriate tabs for the given app state and layout.
    ///
    /// Tabs are dynamic — driven by the libraries available on the connected server.
    /// If the server has no music library, the Music tab doesn't appear.
    static func availableTabs(for appState: AppState, layout: ShellLayout) -> [AppTab] {
        var tabs: [AppTab] = [.home]

        let types = Set(appState.libraries.compactMap(\.collectionType))

        switch layout {
        case .compact:
            // iPhone: limited tabs — Home, one dynamic media tab, Search, Downloads, Settings
            if types.contains(.music) {
                tabs.append(.music)
            } else if types.contains(.movies) {
                tabs.append(.movies)
            } else if types.contains(.tvshows) {
                tabs.append(.tvShows)
            }

        case .regular, .tv:
            // iPad/Mac sidebar & tvOS: show all available media tabs
            if types.contains(.music) { tabs.append(.music) }
            if types.contains(.movies) { tabs.append(.movies) }
            if types.contains(.tvshows) { tabs.append(.tvShows) }
        }

        tabs.append(.search)

        // Downloads only on platforms that support them
        if layout != .tv {
            tabs.append(.downloads)
        }

        tabs.append(.settings)
        return tabs
    }
}
