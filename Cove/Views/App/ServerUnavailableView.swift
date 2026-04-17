import DownloadManager
import SwiftUI

/// A full-screen state shown on the Home tab when the Jellyfin server cannot be reached.
///
/// Provides:
/// - A clear visual explanation of the connectivity issue
/// - A retry button to attempt reconnecting
/// - A shortcut to the Downloads tab so offline content remains accessible
struct ServerUnavailableView: View {
    @Environment(AppState.self) private var appState

    /// Whether the device has no network at all, vs the server specifically being unreachable.
    private var isDeviceOffline: Bool {
        !NetworkMonitor.shared.isConnected
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // MARK: - Icon

            Image(systemName: isDeviceOffline ? "wifi.slash" : "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: appState.isRetryingLibraries)

            // MARK: - Messaging

            VStack(spacing: 8) {
                Text(isDeviceOffline ? "You're Offline" : "Server Unavailable")
                    .font(.title2)
                    .bold()

                Text(
                    isDeviceOffline
                        ? "Connect to the internet to browse your Jellyfin library."
                        : "Could not connect to your Jellyfin server. It may be down or unreachable."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            }

            // MARK: - Actions

            VStack(spacing: 12) {
                Button {
                    Task {
                        await appState.retryLoadLibraries()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if appState.isRetryingLibraries {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Retry")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appState.isRetryingLibraries)

                Button {
                    appState.selectedTab = .downloads
                } label: {
                    Label("Go to Downloads", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Offline") {
        ServerUnavailableView()
            .environment(AppState.preview)
    }
#endif
