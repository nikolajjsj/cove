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
                // Start Radio
                Button {
                    Task { await startRadio() }
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }

                Divider()

                // Favorite / Unfavorite
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    let isFav = artist.userData?.isFavorite == true
                    Label(
                        isFav ? "Unfavorite" : "Favorite",
                        systemImage: isFav ? "heart.fill" : "heart"
                    )
                }
            }
    }

    // MARK: - Actions

    private func startRadio() async {
        do {
            let tracks = try await appState.provider.instantMix(for: artist.id, limit: 50)
            guard !tracks.isEmpty else { return }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
            appState.showToast("Radio started", icon: "dot.radiowaves.left.and.right")
        } catch {
            // Silently fail
        }
    }

    private func toggleFavorite() async {
        let isFav = artist.userData?.isFavorite == true
        do {
            try await appState.provider.setFavorite(itemId: artist.id, isFavorite: !isFav)
            appState.showToast(
                isFav ? "Removed from Favorites" : "Added to Favorites",
                icon: isFav ? "heart" : "heart.fill"
            )
        } catch {
            // Silently fail
        }
    }
}

extension View {
    /// Attaches an artist context menu with Radio and Favorite actions.
    func artistContextMenu(artist: MediaItem) -> some View {
        modifier(ArtistContextMenuModifier(artist: artist))
    }
}
