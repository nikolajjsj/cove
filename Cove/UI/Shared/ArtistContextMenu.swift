import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a context menu to an artist item.
struct ArtistContextMenuModifier: ViewModifier {
    let artist: MediaItem
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Task { await appState.startRadio(for: artist.id) }
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }

                Divider()

                Button {
                    Task {
                        await appState.toggleFavorite(
                            itemId: artist.id,
                            isFavorite: artist.userData?.isFavorite == true
                        )
                    }
                } label: {
                    let isFav = artist.userData?.isFavorite == true
                    Label(
                        isFav ? "Unfavorite" : "Favorite",
                        systemImage: isFav ? "heart.fill" : "heart"
                    )
                }
            }
    }
}

extension View {
    func artistContextMenu(artist: MediaItem) -> some View {
        modifier(ArtistContextMenuModifier(artist: artist))
    }
}
