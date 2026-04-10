import Models
import SwiftUI

/// A self-contained played/watched toggle button for use in menus, context
/// menus, and toolbars.
///
/// Reads the effective played state from ``UserDataStore`` and mutates it
/// optimistically. Shows a toast via ``AppState`` on success or failure.
///
/// ```swift
/// Menu {
///     FavoriteToggle(itemId: item.id, userData: item.userData)
///     PlayedToggle(itemId: item.id, userData: item.userData)
/// } label: {
///     Image(systemName: "ellipsis.circle")
/// }
/// ```
struct PlayedToggle: View {
    let itemId: ItemID
    let userData: UserData?

    @Environment(UserDataStore.self) private var store

    var body: some View {
        let isPlayed = store.isPlayed(itemId, fallback: userData)

        Button {
            togglePlayed()
        } label: {
            Label(
                isPlayed ? "Mark as Unwatched" : "Mark as Watched",
                systemImage: isPlayed ? "eye.slash" : "eye"
            )
        }
    }

    private func togglePlayed() {
        Task {
            do {
                let newValue = try await store.togglePlayed(
                    itemId: itemId, current: userData
                )
                ToastManager.shared.show(
                    newValue ? "Marked as Watched" : "Marked as Unwatched",
                    icon: newValue ? "eye.fill" : "eye.slash"
                )
            } catch {
                ToastManager.shared.show(
                    "Couldn't update watched status",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
            }
        }
    }
}
