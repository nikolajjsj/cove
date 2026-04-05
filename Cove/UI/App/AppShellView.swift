import DownloadManager
import Models
import PlaybackEngine
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab = .home
    @State private var showFullPlayer = false

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .overlay(alignment: .top) {
            if appState.isOffline {
                OfflineIndicatorView()
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isOffline)
        .sheet(isPresented: $showFullPlayer) {
            AudioPlayerView()
        }
    }

    // MARK: - iPhone (compact) — TabView

    private var compactLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(availableTabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    NavigationStack {
                        tab.destination(appState: appState)
                            .navigationTitle(tab.title)
                            .withNavigationDestinations()
                    }
                }
            }
        }
        .tabViewBottomAccessory(isEnabled: appState.audioPlayer.queue.currentTrack != nil) {
            if let track = appState.audioPlayer.queue.currentTrack {
                NowPlayingBar(showFullPlayer: $showFullPlayer, track: track)
            }
        }
    }

    // MARK: - iPad / Mac (regular) — Sidebar

    private var regularLayout: some View {
        NavigationSplitView {
            #if !os(iOS)
                List(availableTabs, id: \.self, selection: $selectedTab) { tab in
                    Label(tab.title, systemImage: tab.icon)
                }
                .navigationTitle("Cove")
            #endif
        } detail: {
            NavigationStack {
                selectedTab.destination(appState: appState)
                    .navigationTitle(selectedTab.title)
                    .withNavigationDestinations()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let track = appState.audioPlayer.queue.currentTrack {
                NowPlayingBar(showFullPlayer: $showFullPlayer, track: track)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(height: 64)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Dynamic Tabs

    private var availableTabs: [AppTab] {
        var tabs: [AppTab] = [.home]
        // On compact (iPhone), only show Home / Downloads / Settings.
        // Library sections are reachable by tapping their header on the Home view.
        if sizeClass != .compact {
            let types = Set(appState.libraries.compactMap(\.collectionType))
            if types.contains(.music) { tabs.append(.music) }
            if types.contains(.movies) { tabs.append(.movies) }
            if types.contains(.tvshows) { tabs.append(.tvShows) }
        }
        tabs.append(.downloads)
        tabs.append(.settings)
        return tabs
    }
}

// MARK: - Tab Enum

enum AppTab: Hashable {
    case home
    case music
    case movies
    case tvShows
    case downloads
    case settings

    var title: String {
        switch self {
        case .home: "Home"
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
        case .music: "music.note"
        case .movies: "film"
        case .tvShows: "tv"
        case .downloads: "arrow.down.circle"
        case .settings: "gear"
        }
    }

    @ViewBuilder
    func destination(appState: AppState) -> some View {
        switch self {
        case .home:
            HomeView()
        case .music:
            MusicLibraryView(library: appState.libraries.first { $0.collectionType == .music })
        case .movies:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .movies })
        case .tvShows:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .tvshows })
        case .downloads:
            if let downloadManager = appState.downloadManager {
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
