import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a comprehensive context menu to an album.
struct AlbumContextMenuModifier: ViewModifier {
    let album: MediaItem
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var showPlaylistPicker = false
    @State private var fetchedTrackIds: [ItemID] = []

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Task { await playAlbum(shuffle: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    Task { await playAlbum(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }

                Divider()

                Button {
                    Task { await queueAlbum(next: true) }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    Task { await queueAlbum(next: false) }
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
                }

                Divider()

                Button {
                    Task { await appState.startRadio(for: album.id) }
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }

                Button {
                    Task { await prepareAndShowPlaylistPicker() }
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                Divider()

                Button {
                    Task {
                        await appState.toggleFavorite(
                            itemId: album.id,
                            isFavorite: album.userData?.isFavorite == true
                        )
                    }
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
            var tracks = try await authManager.provider.tracks(album: album.id)
            guard !tracks.isEmpty else { return }
            if shuffle { tracks.shuffle() }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
        } catch {
            // Silently fail
        }
    }

    private func queueAlbum(next: Bool) async {
        do {
            let tracks = try await authManager.provider.tracks(album: album.id)
            appState.queueTracks(tracks, next: next)
        } catch {
            // Silently fail
        }
    }

    private func prepareAndShowPlaylistPicker() async {
        do {
            let tracks = try await authManager.provider.tracks(album: album.id)
            fetchedTrackIds = tracks.map(\.id)
            showPlaylistPicker = true
        } catch {
            // Silently fail
        }
    }
}

extension View {
    func albumContextMenu(album: MediaItem) -> some View {
        modifier(AlbumContextMenuModifier(album: album))
    }
}
