import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a context menu to a playlist.
struct PlaylistContextMenuModifier: ViewModifier {
    let playlist: Playlist
    var onRenamed: (() -> Void)?
    var onDeleted: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Play
                Button {
                    Task { await playPlaylist(shuffle: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                // Shuffle
                Button {
                    Task { await playPlaylist(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }

                Divider()

                // Play Next
                Button {
                    Task { await queuePlaylist(next: true) }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                // Play Later
                Button {
                    Task { await queuePlaylist(next: false) }
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
                }

                Divider()

                // Rename
                Button {
                    renameText = playlist.name
                    showRenameAlert = true
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }

                // Delete
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
            .alert("Rename Playlist", isPresented: $showRenameAlert) {
                TextField("Playlist name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    Task { await renamePlaylist() }
                }
            }
            .confirmationDialog(
                "Delete \(playlist.name)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    Task { await deletePlaylist() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This playlist will be permanently deleted.")
            }
    }

    // MARK: - Actions

    private func playPlaylist(shuffle: Bool) async {
        do {
            var tracks = try await appState.provider.playlistTracks(playlist: playlist.id)
            guard !tracks.isEmpty else { return }
            if shuffle { tracks.shuffle() }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
        } catch {
            // Silently fail
        }
    }

    private func queuePlaylist(next: Bool) async {
        do {
            let tracks = try await appState.provider.playlistTracks(playlist: playlist.id)
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

    private func renamePlaylist() async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await appState.provider.renamePlaylist(playlist: playlist.id, name: name)
            appState.showToast("Playlist renamed", icon: "checkmark.circle.fill")
            onRenamed?()
        } catch {
            // Silently fail
        }
    }

    private func deletePlaylist() async {
        do {
            try await appState.provider.deletePlaylist(playlist: playlist.id)
            appState.showToast("Playlist deleted", icon: "checkmark.circle.fill")
            onDeleted?()
        } catch {
            // Silently fail
        }
    }
}

extension View {
    /// Attaches a playlist context menu with Play, Shuffle, Play Next/Later,
    /// Rename, and Delete actions.
    func playlistContextMenu(
        playlist: Playlist,
        onRenamed: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PlaylistContextMenuModifier(
                playlist: playlist, onRenamed: onRenamed, onDeleted: onDeleted))
    }
}
