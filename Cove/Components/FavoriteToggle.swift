import Models
import SwiftUI

/// A self-contained favorite toggle button for use in menus, context menus,
/// and toolbars.
///
/// Reads the effective favorite state from ``UserDataStore`` and mutates it
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
struct FavoriteToggle: View {
    let itemId: ItemID
    let userData: UserData?

    @Environment(UserDataStore.self) private var store
    @Environment(AppState.self) private var appState

    var body: some View {
        let isFav = store.isFavorite(itemId, fallback: userData)

        Button {
            toggleFavorite()
        } label: {
            Label(
                isFav ? "Unfavorite" : "Favorite",
                systemImage: isFav ? "heart.fill" : "heart"
            )
        }
    }

    private func toggleFavorite() {
        Task {
            do {
                let newValue = try await store.toggleFavorite(
                    itemId: itemId, current: userData
                )
                appState.showToast(
                    newValue ? "Added to Favorites" : "Removed from Favorites",
                    icon: newValue ? "heart.fill" : "heart"
                )
            } catch {
                appState.showToast(
                    "Couldn't update favorite",
                    icon: "exclamationmark.triangle"
                )
            }
        }
    }
}
