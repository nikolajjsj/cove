import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a comprehensive context menu to a track.
///
/// Usage:
/// ```swift
/// TrackRow(track: track)
///     .trackContextMenu(track: track)
/// ```
struct TrackContextMenuModifier: ViewModifier {
    let track: Track
    @Environment(AppState.self) private var appState
    @State private var showPlaylistPicker = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Play Next
                Button {
                    appState.audioPlayer.queue.addNext(track)
                    appState.showToast("Playing Next", icon: "text.line.first.and.arrowforward")
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowforward")
                }

                // Play Later
                Button {
                    appState.audioPlayer.queue.addToEnd(track)
                    appState.showToast("Added to Up Next", icon: "text.line.last.and.arrowforward")
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowforward")
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
                    showPlaylistPicker = true
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                Divider()

                // Go to Album
                if let albumId = track.albumId {
                    Button {
                        let albumItem = MediaItem(
                            id: ItemID(albumId.rawValue),
                            title: track.albumName ?? "",
                            mediaType: .album
                        )
                        appState.navigate(to: .music, destination: albumItem)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }

                // Go to Artist
                if let artistId = track.artistId {
                    Button {
                        let artistItem = MediaItem(
                            id: ItemID(artistId.rawValue),
                            title: track.artistName ?? "",
                            mediaType: .artist
                        )
                        appState.navigate(to: .music, destination: artistItem)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }

                Divider()

                // Favorite / Unfavorite
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    let isFav = track.userData?.isFavorite == true
                    Label(
                        isFav ? "Unfavorite" : "Favorite",
                        systemImage: isFav ? "heart.fill" : "heart"
                    )
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                PlaylistPickerSheet(trackIds: [track.id])
            }
    }

    // MARK: - Actions

    private func startRadio() async {
        do {
            let tracks = try await appState.provider.instantMix(for: track.id, limit: 50)
            guard !tracks.isEmpty else { return }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
            appState.showToast("Radio started", icon: "dot.radiowaves.left.and.right")
        } catch {
            // Silently fail
        }
    }

    private func toggleFavorite() async {
        let isFav = track.userData?.isFavorite == true
        do {
            try await appState.provider.setFavorite(itemId: track.id, isFavorite: !isFav)
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
    /// Attaches a music track context menu with Play Next, Play Later, Radio,
    /// Add to Playlist, Go to Album/Artist, and Favorite actions.
    func trackContextMenu(track: Track) -> some View {
        modifier(TrackContextMenuModifier(track: track))
    }
}
