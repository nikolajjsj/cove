import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ZStack {
            // MARK: - Main App Content

            mainContent

            // MARK: - Video Player Overlay

            // Presented as a root-level ZStack layer so it covers everything —
            // tab bars, navigation bars, sheets — with no modal dismiss gesture
            // to interfere with player controls.
            if coordinator.isPresented,
                let item = coordinator.currentItem,
                let streamInfo = coordinator.streamInfo
            {
                VideoPlayerView(
                    item: item,
                    streamInfo: streamInfo,
                    startPosition: coordinator.startPosition
                )
                .environment(appState)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 1.04))
                            .animation(.easeOut(duration: 0.35)),
                        removal: .opacity
                            .animation(.easeIn(duration: 0.25))
                    )
                )
                .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: coordinator.isPresented)
        .animation(.easeInOut(duration: 0.4), value: appState.isRestoringSession)
        .animation(.easeInOut(duration: 0.4), value: appState.isAuthenticated)
        // Playback error alert — shown at the root so it's always reachable
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { coordinator.showError },
                set: { coordinator.showError = $0 }
            )
        ) {
            Button("OK", role: .cancel) {
                coordinator.error = nil
            }
        } message: {
            if let error = coordinator.error {
                Text(
                    "Could not play \"\(error.itemTitle)\".\n\(error.localizedDescription)"
                )
            }
        }
        .task {
            await appState.restoreSession()
        }
    }

    // MARK: - Main Content (Launch / App / Sign-In)

    @ViewBuilder
    private var mainContent: some View {
        if appState.isRestoringSession {
            LaunchView()
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
        } else if appState.isAuthenticated {
            AppShellView()
                .transition(.opacity.animation(.easeIn(duration: 0.35)))
        } else {
            ServerConnectView()
                .transition(.opacity.animation(.easeIn(duration: 0.35)))
        }
    }
}
