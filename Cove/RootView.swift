import Models
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

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
                .environment(authManager)
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
        .animation(.easeInOut(duration: 0.4), value: authManager.isRestoringSession)
        .animation(.easeInOut(duration: 0.4), value: authManager.isAuthenticated)
        // Resume prompt — "Resume" vs "Play from Beginning"
        .alert(
            "Resume Playback",
            isPresented: Binding(
                get: { coordinator.showResumePrompt },
                set: { coordinator.showResumePrompt = $0 }
            )
        ) {
            Button("Resume") {
                coordinator.resumePlayback()
            }
            Button("Play from Beginning") {
                coordinator.playFromBeginning()
            }
            Button("Cancel", role: .cancel) {
                coordinator.cancelResume()
            }
        } message: {
            if let item = coordinator.currentItem {
                Text(
                    "You were \(TimeFormatting.playbackPosition(coordinator.savedPosition)) into \"\(item.title)\". Would you like to resume?"
                )
            }
        }
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
        if authManager.isRestoringSession {
            LaunchView()
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
        } else if authManager.isAuthenticated {
            AppShellView()
                .transition(.opacity.animation(.easeIn(duration: 0.35)))
        } else {
            ServerConnectView()
                .transition(.opacity.animation(.easeIn(duration: 0.35)))
        }
    }
}
