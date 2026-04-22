import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// Adaptive track-info header for the full-screen audio player.
///
/// In artwork mode (`showThumbnail: false`) it renders as a large title/artist
/// row with action buttons — placed below the album art.
/// In secondary mode (`showThumbnail: true`) it prepends a compact thumbnail
/// and uses smaller typography — placed at the top of the queue/lyrics view.
///
/// Optionally injects a `CurrentLyricPreview` below the artist line when
/// `showLyricPreview` is `true`.
struct PlayerTrackInfoRow: View {
    let track: Track
    var showThumbnail: Bool = false
    var showLyricPreview: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPlaylistPicker = false

    var body: some View {
        HStack(alignment: .center, spacing: showThumbnail ? 14 : 0) {
            // Compact thumbnail — secondary mode only
            if showThumbnail {
                MediaImage.trackThumbnail(url: artworkURL(for: track), cornerRadius: 8)
                    .frame(width: 52, height: 52)
                    .animation(.easeInOut(duration: 0.3), value: track.id)
            }

            // Title, artist, optional live-lyric preview
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(showThumbnail ? .headline : .title2.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let artistName = track.artistName {
                    Text(artistName)
                        .font(showThumbnail ? .subheadline : .title3)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                if showLyricPreview {
                    CurrentLyricPreview(track: track)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: track.id)

            Menu {
                FavoriteButton(track: track)
                Divider()
                Button {
                    appState.audioPlayer.queue.addNext(track)
                    ToastManager.shared.show(
                        "Playing Next", icon: "text.line.first.and.arrowtriangle.forward")
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    appState.audioPlayer.queue.addToEnd(track)
                    ToastManager.shared.show(
                        "Added to Up Next", icon: "text.line.last.and.arrowtriangle.forward")
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
                }

                Divider()

                Button {
                    showPlaylistPicker = true
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                if let albumId = track.albumId {
                    Button {
                        let albumItem = MediaItem(
                            id: ItemID(albumId.rawValue),
                            title: track.albumName ?? "",
                            mediaType: .album
                        )
                        appState.navigate(to: .music, destination: albumItem)
                        dismiss()
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
                        dismiss()
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, showThumbnail ? 14 : 0)
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerSheet(trackIds: [track.id])
        }
    }

    private func artworkURL(for track: Track) -> URL? {
        let itemId = track.albumId ?? track.id
        return authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 96, height: 96))
    }
}

// MARK: - Favorite Button (Isolated)

/// Small isolated view so the favorite API call / optimistic toggle
/// doesn't cause the parent to re-render.
private struct FavoriteButton: View {
    let track: Track
    @Environment(UserDataStore.self) private var store

    var body: some View {
        let isFav = store.isFavorite(track.id, fallback: track.userData)

        Button(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "heart.fill" : "heart") {
            Task {
                do {
                    let newValue = try await store.toggleFavorite(
                        itemId: track.id, current: track.userData
                    )
                    ToastManager.shared.show(
                        newValue ? "Added to Favorites" : "Removed from Favorites",
                        icon: newValue ? "heart.fill" : "heart"
                    )
                } catch {
                    // TODO: Silently fail
                }
            }
        }
    }
}

