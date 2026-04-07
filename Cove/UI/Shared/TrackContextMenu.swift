import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A view modifier that attaches a comprehensive context menu to a track.
struct TrackContextMenuModifier: ViewModifier {
    let track: Track
    @Environment(AppState.self) private var appState
    @State private var showPlaylistPicker = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    appState.audioPlayer.queue.addNext(track)
                    appState.showToast(
                        "Playing Next", icon: "text.line.first.and.arrowtriangle.forward")
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    appState.audioPlayer.queue.addToEnd(track)
                    appState.showToast(
                        "Added to Up Next", icon: "text.line.last.and.arrowtriangle.forward")
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
                }

                Divider()

                Button {
                    Task { await appState.startRadio(for: track.id) }
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }

                Button {
                    showPlaylistPicker = true
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                Divider()

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

                Button {
                    Task {
                        await appState.toggleFavorite(
                            itemId: track.id,
                            isFavorite: track.userData?.isFavorite == true
                        )
                    }
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
}

extension View {
    func trackContextMenu(track: Track) -> some View {
        modifier(TrackContextMenuModifier(track: track))
    }
}
