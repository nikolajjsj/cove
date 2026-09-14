import Defaults
import ImageService
import JellyfinProvider
import SwiftUI

/// A settings view for managing cached data such as images and API responses.
struct CacheManagementView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState
    @Default(.keepArtworkOffline) private var keepArtworkOffline
    @Default(.artworkOverCellular) private var artworkOverCellular

    @State private var isClearing = false
    @State private var showClearConfirmation = false
    @State private var pendingAction: ClearAction = .imageOnly

    var body: some View {
        List {
            Section {
                Text(
                    "Cove caches images and API responses to improve performance and reduce data usage. Clearing the cache won't delete your downloads or account data."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep All Artwork on Device", isOn: $keepArtworkOffline)
                    .onChange(of: keepArtworkOffline) { _, on in
                        ImageService.setKeepsAllArtwork(on)
                        if on {
                            appState.prefetchArtworkNow()
                        } else {
                            appState.artworkCache.cancel()
                        }
                    }
                if keepArtworkOffline {
                    Toggle("Use Cellular Data", isOn: $artworkOverCellular)
                    ArtworkCacheStatusRow(cache: appState.artworkCache)
                    Button("Cache Artwork Now", systemImage: "arrow.down.circle") {
                        appState.prefetchArtworkNow()
                    }
                    .disabled(appState.artworkCache.isRunning)
                }
            } header: {
                Text("Offline Artwork")
            } footer: {
                Text(
                    keepArtworkOffline
                        ? "Every poster, thumbnail and backdrop in your library is downloaded once and kept, so the app looks the same without a connection. A whole library is typically a few hundred megabytes to a couple of gigabytes."
                        : "Artwork is cached as you browse and trimmed to 500 MB. Turn this on to download all of it up front for offline use."
                )
            }

            Section("Actions") {
                Button("Clear Image Cache", systemImage: "photo.stack", role: .destructive) {
                    pendingAction = .imageOnly
                    showClearConfirmation = true
                }
                .disabled(isClearing)

                Button("Clear All Caches", systemImage: "trash", role: .destructive) {
                    pendingAction = .all
                    showClearConfirmation = true
                }
                .disabled(isClearing)
            }
        }
        .navigationTitle("Cache")
        .confirmationDialog(
            "Clear Cache?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(pendingAction.confirmButtonLabel, role: .destructive) {
                performClear(pendingAction)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingAction.confirmMessage)
        }
    }

    // MARK: - Actions

    private func performClear(_ action: ClearAction) {
        isClearing = true

        switch action {
        case .imageOnly:
            appState.artworkCache.cancel()
            ImageService.clearCache()
            isClearing = false
            ToastManager.shared.show("Image cache cleared", icon: "checkmark.circle")
            Task { await appState.artworkCache.refreshUsage() }

        case .all:
            appState.artworkCache.cancel()
            ImageService.clearCache()
            URLCache.shared.removeAllCachedResponses()

            Task {
                await authManager.provider.clearCache()
                await appState.artworkCache.refreshUsage()
                isClearing = false
                ToastManager.shared.show("All caches cleared", icon: "checkmark.circle")
            }
        }
    }
}

// MARK: - Clear Action

extension CacheManagementView {
    /// The type of cache clear operation the user selected.
    enum ClearAction {
        case imageOnly
        case all

        /// The label for the destructive confirmation button.
        var confirmButtonLabel: String {
            switch self {
            case .imageOnly: "Clear Image Cache"
            case .all: "Clear All Caches"
            }
        }

        /// The explanatory message shown in the confirmation dialog.
        var confirmMessage: String {
            switch self {
            case .imageOnly:
                "This will remove cached images. They will be re-downloaded as needed."
            case .all:
                "This will remove cached images and API data. They will be re-downloaded as needed."
            }
        }
    }
}

// MARK: - Artwork status

/// "2,140 of 6,812" while it runs; "1.3 GB on device" when it is done.
private struct ArtworkCacheStatusRow: View {
    let cache: ArtworkCache

    var body: some View {
        LabeledContent("Artwork") {
            HStack(spacing: 6) {
                if cache.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .task { await cache.refreshUsage() }
    }

    private var statusText: String {
        switch cache.status {
        case .running(let done, let total):
            return "\(done.formatted()) of \(total.formatted())"
        case .waitingForWiFi:
            return "Waiting for Wi-Fi"
        case .failed(let message):
            return message
        case .idle:
            let size = ByteCountFormatter.string(fromByteCount: Int64(cache.bytesOnDisk), countStyle: .file)
            return "\(size) on device"
        }
    }
}
