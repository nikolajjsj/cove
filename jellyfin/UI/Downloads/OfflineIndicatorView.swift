import DownloadManager
import SwiftUI

/// A small capsule banner that appears when the device has no network connectivity.
///
/// Place this view in a `ZStack` or `overlay` so it floats above other content.
/// It automatically observes `NetworkMonitor.shared` and shows/hides with animation.
///
/// ```swift
/// NavigationStack {
///     MyContentView()
///         .overlay(alignment: .top) {
///             OfflineIndicatorView()
///         }
/// }
/// ```
struct OfflineIndicatorView: View {
    @State private var isOffline = false

    var body: some View {
        Group {
            if isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .fontWeight(.semibold)

                    Text("Offline Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isOffline)
        .task {
            await monitorConnectivity()
        }
        .onAppear {
            // Seed initial state synchronously so the banner is correct
            // before the first async yield from the stream.
            isOffline = !NetworkMonitor.shared.isConnected
        }
    }

    // MARK: - Private

    /// Continuously observes the shared `NetworkMonitor` connectivity stream
    /// and updates `isOffline` on each change. The `for await` loop suspends
    /// cooperatively and terminates when the view's task is cancelled.
    private func monitorConnectivity() async {
        // Ensure the monitor is running. Calling `start()` multiple times is
        // safe — subsequent calls are no-ops.
        NetworkMonitor.shared.start()

        for await connected in NetworkMonitor.shared.connectivityUpdates {
            isOffline = !connected
        }
    }
}

// MARK: - Toolbar Variant

/// A more compact offline indicator designed for use inside a `ToolbarItem`.
/// Shows only the icon when offline, nothing when online.
struct OfflineToolbarIndicator: View {
    @State private var isOffline = false

    var body: some View {
        Group {
            if isOffline {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)
                    .help("No network connection — offline mode")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isOffline)
        .task {
            NetworkMonitor.shared.start()
            for await connected in NetworkMonitor.shared.connectivityUpdates {
                isOffline = !connected
            }
        }
        .onAppear {
            isOffline = !NetworkMonitor.shared.isConnected
        }
    }
}

// MARK: - Preview

#Preview("Offline Indicator") {
    VStack(spacing: 40) {
        Text("Content goes here")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .overlay(alignment: .top) {
        OfflineIndicatorView()
            .padding(.top, 8)
    }
}
