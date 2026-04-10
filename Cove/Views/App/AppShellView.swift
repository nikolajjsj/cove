import DownloadManager
import Models
import PlaybackEngine
import SwiftUI

/// The main app shell that adapts its navigation paradigm to the current platform.
///
/// - iPhone (compact): Bottom `TabView`
/// - iPad / Mac (regular): `NavigationSplitView` with sidebar
/// - tvOS: Top `TabView` with focus-driven navigation
struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.platformCapabilities) private var capabilities

    #if !os(tvOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var showFullPlayer = false

    var body: some View {
        Group {
            #if os(tvOS)
                TVTabShell()
            #else
                if sizeClass == .compact {
                    CompactTabShell(showFullPlayer: $showFullPlayer)
                } else {
                    SidebarShell(showFullPlayer: $showFullPlayer)
                }
            #endif
        }
        .overlay(alignment: .top) {
            if appState.isOffline {
                OfflineIndicatorView()
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isOffline)
        #if !os(tvOS)
            .sheet(isPresented: $showFullPlayer) {
                AudioPlayerView()
            }
        #endif
    }
}

// MARK: - iPhone (compact) — Bottom Tab Bar

/// The bottom tab bar layout used on iPhone.
private struct CompactTabShell: View {
    @Environment(AppState.self) private var appState
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @Binding var showFullPlayer: Bool

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            ForEach(AppTab.availableTabs(for: appState, layout: .compact), id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    NavigationStack(path: navigationPathBinding(for: tab)) {
                        tab.destination(
                            appState: appState, downloadCoordinator: downloadCoordinator
                        )
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

    private func navigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        @Bindable var appState = appState
        return Binding(
            get: { appState.navigationPaths[tab] ?? NavigationPath() },
            set: { appState.navigationPaths[tab] = $0 }
        )
    }
}

// MARK: - iPad / Mac (regular) — Sidebar

/// The sidebar layout used on iPad and Mac.
private struct SidebarShell: View {
    @Environment(AppState.self) private var appState
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @Binding var showFullPlayer: Bool

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            #if !os(iOS)
                List(
                    AppTab.availableTabs(for: appState, layout: .regular),
                    id: \.self,
                    selection: $appState.selectedTab
                ) { tab in
                    Label(tab.title, systemImage: tab.icon)
                }
                .navigationTitle("Cove")
            #endif
        } detail: {
            NavigationStack(path: navigationPathBinding(for: appState.selectedTab)) {
                appState.selectedTab.destination(
                    appState: appState, downloadCoordinator: downloadCoordinator
                )
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

    private func navigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        @Bindable var appState = appState
        return Binding(
            get: { appState.navigationPaths[tab] ?? NavigationPath() },
            set: { appState.navigationPaths[tab] = $0 }
        )
    }
}

// MARK: - tvOS — Top Tab Bar

/// The top tab bar layout used on Apple TV, with focus-driven navigation.
#if os(tvOS)
    private struct TVTabShell: View {
        @Environment(AppState.self) private var appState
        @Environment(DownloadCoordinator.self) private var downloadCoordinator

        var body: some View {
            @Bindable var appState = appState

            TabView(selection: $appState.selectedTab) {
                ForEach(AppTab.availableTabs(for: appState, layout: .tv), id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        NavigationStack(path: navigationPathBinding(for: tab)) {
                            tab.destination(
                                appState: appState, downloadCoordinator: downloadCoordinator
                            )
                            .navigationTitle(tab.title)
                            .withNavigationDestinations()
                        }
                    }
                }
            }
        }

        private func navigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
            @Bindable var appState = appState
            return Binding(
                get: { appState.navigationPaths[tab] ?? NavigationPath() },
                set: { appState.navigationPaths[tab] = $0 }
            )
        }
    }
#endif
