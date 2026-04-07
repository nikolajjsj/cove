import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a comprehensive context menu to an album.
///
/// Usage:
/// ```swift
/// AlbumCard(album: album)
///     .albumContextMenu(album: album)
/// ```
struct AlbumContextMenuModifier: ViewModifier {
    let album: MediaItem
    @Environment(AppState.self) private var appState
    @State private var showPlaylistPicker = false
    @State private var fetchedTrackIds: [ItemID] = []

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Play
                Button {
                    Task { await playAlbum(shuffle: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                // Shuffle
                Button {
                    Task { await playAlbum(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }

                Divider()

                // Play Next
                Button {
                    Task { await queueAlbum(next: true) }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                // Play Later
                Button {
                    Task { await queueAlbum(next: false) }
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
                }

                Divider()

                // Start Radio
                Button {
                    Task { await startRadio() }
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }

                // Add to Playlist
                Button {
                    Task { await prepareAndShowPlaylistPicker() }
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                Divider()

                // Favorite / Unfavorite
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    let isFav = album.userData?.isFavorite == true
                    Label(
                        isFav ? "Unfavorite" : "Favorite",
                        systemImage: isFav ? "heart.fill" : "heart"
                    )
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                PlaylistPickerSheet(trackIds: fetchedTrackIds)
            }
    }

    // MARK: - Actions

    private func playAlbum(shuffle: Bool) async {
        do {
            var tracks = try await appState.provider.tracks(album: album.id)
            guard !tracks.isEmpty else { return }
            if shuffle { tracks.shuffle() }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
        } catch {
            // Silently fail
        }
    }

    private func queueAlbum(next: Bool) async {
        do {
            let tracks = try await appState.provider.tracks(album: album.id)
            guard !tracks.isEmpty else { return }
            for track in tracks {
                if next {
                    appState.audioPlayer.queue.addNext(track)
                } else {
                    appState.audioPlayer.queue.addToEnd(track)
                }
            }
            let message = next ? "Playing Next" : "Added to Up Next"
            let icon =
                next
                ? "text.line.first.and.arrowtriangle.forward" : "text.line.last.and.arrowtriangle.forward"
            appState.showToast(message, icon: icon)
        } catch {
            // Silently fail
        }
    }

    private func startRadio() async {
        do {
            let tracks = try await appState.provider.instantMix(for: album.id, limit: 50)
            guard !tracks.isEmpty else { return }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
            appState.showToast("Radio started", icon: "dot.radiowaves.left.and.right")
        } catch {
            // Silently fail
        }
    }

    private func prepareAndShowPlaylistPicker() async {
        do {
            let tracks = try await appState.provider.tracks(album: album.id)
            fetchedTrackIds = tracks.map(\.id)
            showPlaylistPicker = true
        } catch {
            // Silently fail
        }
    }

    private func toggleFavorite() async {
        let isFav = album.userData?.isFavorite == true
        do {
            try await appState.provider.setFavorite(itemId: album.id, isFavorite: !isFav)
            appState.showToast(
                isFav ? "Removed from Favorites" : "Added to Favorites",
                icon: isFav ? "heart" : "heart.fill"
            )
        } catch {
            // Silently fail
        }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches an album context menu with Play, Shuffle, Play Next/Later,
    /// Radio, Add to Playlist, and Favorite actions.
    func albumContextMenu(album: MediaItem) -> some View {
        modifier(AlbumContextMenuModifier(album: album))
    }
}
