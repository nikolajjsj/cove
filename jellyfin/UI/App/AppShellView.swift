import Models
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab = .home

    var body: some View {
        if sizeClass == .compact {
            compactLayout
        } else {
            regularLayout
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
                    }
                }
            }
        }
    }

    // MARK: - iPad / Mac (regular) — Sidebar

    private var regularLayout: some View {
        NavigationSplitView {
            List(availableTabs, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationTitle("Cove")
        } detail: {
            NavigationStack {
                selectedTab.destination(appState: appState)
                    .navigationTitle(selectedTab.title)
            }
        }
    }

    // MARK: - Dynamic Tabs

    private var availableTabs: [AppTab] {
        var tabs: [AppTab] = [.home]
        let types = Set(appState.libraries.compactMap(\.collectionType))
        if types.contains(.movies) { tabs.append(.movies) }
        if types.contains(.tvshows) { tabs.append(.tvShows) }
        if types.contains(.music) { tabs.append(.music) }
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
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .music: "music.note"
        case .movies: "film"
        case .tvShows: "tv"
        case .settings: "gear"
        }
    }

    @ViewBuilder
    func destination(appState: AppState) -> some View {
        switch self {
        case .home:
            HomeView()
        case .music:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .music })
        case .movies:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .movies })
        case .tvShows:
            LibraryGridView(library: appState.libraries.first { $0.collectionType == .tvshows })
        case .settings:
            SettingsView()
        }
    }
}
