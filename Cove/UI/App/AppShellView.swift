import DownloadManager
import Models
import PlaybackEngine
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showFullPlayer = false

    var body: some View {
        @Bindable var appState = appState

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
        .toastOverlay(toast: $appState.currentToast)
        .sheet(isPresented: $showFullPlayer) {
            AudioPlayerView()
        }
    }

    // MARK: - iPhone (compact) — TabView

    private var compactLayout: some View {
        @Bindable var appState = appState

        return TabView(selection: $appState.selectedTab) {
            ForEach(availableTabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    NavigationStack(path: navigationPathBinding(for: tab)) {
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
        @Bindable var appState = appState

        return NavigationSplitView {
            #if !os(iOS)
                List(availableTabs, id: \.self, selection: $appState.selectedTab) { tab in
                    Label(tab.title, systemImage: tab.icon)
                }
                .navigationTitle("Cove")
            #endif
        } detail: {
            NavigationStack(path: navigationPathBinding(for: appState.selectedTab)) {
                appState.selectedTab.destination(appState: appState)
                    .navigationTitle(appState.selectedTab.title)
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
        var tabs: [AppTab] = [.home, .search]
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

    // MARK: - Navigation Path Binding

    /// Creates a `Binding<NavigationPath>` for a given tab, backed by `appState.navigationPaths`.
    private func navigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        @Bindable var appState = appState
        return Binding(
            get: { appState.navigationPaths[tab] ?? NavigationPath() },
            set: { appState.navigationPaths[tab] = $0 }
        )
    }
}
