import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
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
        .animation(.easeInOut(duration: 0.4), value: appState.isRestoringSession)
        .animation(.easeInOut(duration: 0.4), value: appState.isAuthenticated)
        .task {
            await appState.restoreSession()
        }
    }
}
