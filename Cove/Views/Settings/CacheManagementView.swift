import ImageService
import SwiftUI

/// A settings view for managing cached data such as images and API responses.
struct CacheManagementView: View {
    @Environment(AuthManager.self) private var authManager

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
            ImageService.clearCache()
            isClearing = false
            ToastManager.shared.show("Image cache cleared", icon: "checkmark.circle")

        case .all:
            ImageService.clearCache()
            URLCache.shared.removeAllCachedResponses()

            Task {
                await authManager.provider.clearCache()
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
