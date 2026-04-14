import ImageService
import SwiftUI

/// A settings view for managing cached data such as images and API responses.
struct CacheManagementView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var isClearing = false
    @State private var clearAction: ClearAction?

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
                    clearAction = .imageOnly
                }
                .disabled(isClearing)

                Button("Clear All Caches", systemImage: "trash", role: .destructive) {
                    clearAction = .all
                }
                .disabled(isClearing)
            }
        }
        .navigationTitle("Cache")
        .confirmationDialog(
            "Clear Cache?",
            isPresented: showClearConfirmation,
            titleVisibility: .visible
        ) {
            switch clearAction {
            case .imageOnly:
                Button("Clear Image Cache", role: .destructive) {
                    clearImageCache()
                }
            case .all:
                Button("Clear All Caches", role: .destructive) {
                    clearAllCaches()
                }
            case nil:
                EmptyView()
            }

            Button("Cancel", role: .cancel) {
                clearAction = nil
            }
        } message: {
            switch clearAction {
            case .imageOnly:
                Text("This will remove cached images. They will be re-downloaded as needed.")
            case .all:
                Text(
                    "This will remove cached images and API data. They will be re-downloaded as needed."
                )
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: - Confirmation Binding

    private var showClearConfirmation: Binding<Bool> {
        Binding(
            get: { clearAction != nil },
            set: { if !$0 { clearAction = nil } }
        )
    }

    // MARK: - Actions

    private func clearImageCache() {
        isClearing = true
        ImageService.clearCache()
        isClearing = false
        ToastManager.shared.show("Image cache cleared", icon: "checkmark.circle")
    }

    private func clearAllCaches() {
        isClearing = true
        ImageService.clearCache()
        URLCache.shared.removeAllCachedResponses()

        Task {
            await authManager.provider.clearCache()
            isClearing = false
            ToastManager.shared.show("All caches cleared", icon: "checkmark.circle")
        }
    }
}

// MARK: - Clear Action

extension CacheManagementView {
    /// The type of cache clear operation the user selected.
    enum ClearAction: Identifiable {
        case imageOnly
        case all

        var id: Self { self }
    }
}
