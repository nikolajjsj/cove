import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A unified context menu for any media item type.
///
/// Automatically shows the appropriate actions based on `item.mediaType`:
/// - **Movie/Episode**: Play, Mark Watched, Navigate to Series, Favorite
/// - **Series**: Mark Watched, Favorite
/// - **Album**: Play, Shuffle, Queue, Radio, Add to Playlist, Favorite
/// - **Artist**: Radio, Favorite
/// - **Track**: Queue, Radio, Add to Playlist, Navigate to Album/Artist, Favorite
/// - **Collection** and others: Favorite
///
/// Usage:
/// ```swift
/// LibraryItemCard(item: item)
///     .mediaContextMenu(item: item)
///
/// // For Track models (preserves artistId for "Go to Artist"):
/// SongRow(track: track)
///     .mediaContextMenu(track: track)
/// ```
struct MediaContextMenuModifier: ViewModifier {
    let item: MediaItem

    /// Optional artist ID, only available when constructed from a `Track` model.
    /// Enables the "Go to Artist" action for songs.
    let artistId: ArtistID?

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var showPlaylistPicker = false
    @State private var fetchedTrackIds: [ItemID] = []

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    func body(content: Content) -> some View {
        content
            .contextMenu { menuContent }
            .sheet(isPresented: $showPlaylistPicker) {
                PlaylistPickerSheet(trackIds: fetchedTrackIds)
            }
    }

    // MARK: - Menu Dispatch

    @ViewBuilder
    private var menuContent: some View {
        switch item.mediaType {
        case .movie:
            movieMenu
        case .episode:
            episodeMenu
        case .series:
            seriesMenu
        case .album:
            albumMenu
        case .artist:
            artistMenu
        case .track:
            trackMenu
        case .collection, .season, .genre, .book, .podcast, .playlist:
            defaultMenu
        }
    }

    // MARK: - Movie Menu

    @ViewBuilder
    private var movieMenu: some View {
        playVideoButton
        Divider()
        PlayedToggle(itemId: item.id, userData: item.userData)
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Episode Menu

    @ViewBuilder
    private var episodeMenu: some View {
        playVideoButton

        Divider()

        PlayedToggle(itemId: item.id, userData: item.userData)

        if let seriesId = item.seriesId {
            Button {
                let series = MediaItem(
                    id: seriesId,
                    title: item.seriesName ?? "",
                    mediaType: .series
                )
                appState.navigate(to: .tvShows, destination: series)
            } label: {
                Label("Go to Series", systemImage: "tv")
            }
        }

        Divider()

        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Series Menu

    @ViewBuilder
    private var seriesMenu: some View {
        PlayedToggle(itemId: item.id, userData: item.userData)
        Divider()
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Album Menu

    @ViewBuilder
    private var albumMenu: some View {
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

        radioButton

        Button {
            Task { await prepareAlbumForPlaylistPicker() }
        } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }

        Divider()

        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Artist Menu

    @ViewBuilder
    private var artistMenu: some View {
        radioButton
        Divider()
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Track Menu

    @ViewBuilder
    private var trackMenu: some View {
        Button {
            appState.audioPlayer.queue.addNext(item.asTrack)
            appState.showToast(
                "Playing Next", icon: "text.line.first.and.arrowtriangle.forward")
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            appState.audioPlayer.queue.addToEnd(item.asTrack)
            appState.showToast(
                "Added to Up Next", icon: "text.line.last.and.arrowtriangle.forward")
        } label: {
            Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        Divider()

        radioButton

        Button {
            fetchedTrackIds = [item.id]
            showPlaylistPicker = true
        } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }

        Divider()

        if let albumId = item.albumId {
            Button {
                let album = MediaItem(
                    id: albumId,
                    title: item.albumName ?? "",
                    mediaType: .album
                )
                appState.navigate(to: .music, destination: album)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if let artistId {
            Button {
                let artist = MediaItem(
                    id: ItemID(artistId.rawValue),
                    title: item.artistName ?? "",
                    mediaType: .artist
                )
                appState.navigate(to: .music, destination: artist)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }

        Divider()

        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Default Menu

    @ViewBuilder
    private var defaultMenu: some View {
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Shared Action Buttons

    /// Play or resume a video item (movie or episode).
    private var playVideoButton: some View {
        Button {
            coordinator.play(item: item, using: authManager.provider)
        } label: {
            let hasProgress = (item.userData?.playbackPosition ?? 0) > 0
            Label(
                hasProgress ? "Resume" : "Play",
                systemImage: "play.fill"
            )
        }
    }

    /// Start an instant-mix radio station seeded from this item.
    private var radioButton: some View {
        Button {
            Task { await appState.startRadio(for: item.id) }
        } label: {
            Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    // MARK: - Album Actions

    private func playAlbum(shuffle: Bool) async {
        do {
            var tracks = try await authManager.provider.tracks(album: item.id)
            guard !tracks.isEmpty else { return }
            if shuffle { tracks.shuffle() }
            appState.audioPlayer.play(tracks: tracks, startingAt: 0)
        } catch {
            // Silently fail — the UI doesn't need an error for background queue ops
        }
    }

    private func queueAlbum(next: Bool) async {
        do {
            let tracks = try await authManager.provider.tracks(album: item.id)
            appState.queueTracks(tracks, next: next)
        } catch {
            // Silently fail
        }
    }

    private func prepareAlbumForPlaylistPicker() async {
        do {
            let tracks = try await authManager.provider.tracks(album: item.id)
            fetchedTrackIds = tracks.map(\.id)
            showPlaylistPicker = true
        } catch {
            // Silently fail
        }
    }
}

// MARK: - MediaItem ↔ Track Conversion

extension MediaItem {
    /// Lightweight conversion to a `Track` for audio queue operations.
    ///
    /// Populated from the fields that `MediaItem` carries for audio items.
    /// Used internally by the context menu for Play Next / Play Later actions.
    var asTrack: Track {
        Track(
            id: TrackID(id.rawValue),
            title: title,
            albumId: albumId.map { AlbumID($0.rawValue) },
            albumName: albumName,
            artistName: artistName,
            duration: runtime,
            userData: userData
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Attaches a context menu appropriate for the given media item's type.
    ///
    /// The menu automatically adapts its actions based on `item.mediaType`:
    /// movies/episodes get video playback actions, albums/tracks get audio
    /// queue actions, and everything gets a favorite toggle.
    func mediaContextMenu(item: MediaItem) -> some View {
        modifier(MediaContextMenuModifier(item: item, artistId: nil))
    }

    /// Attaches a context menu for a `Track`, preserving the artist ID
    /// so that "Go to Artist" navigation works.
    func mediaContextMenu(track: Track) -> some View {
        let item = MediaItem(
            id: ItemID(track.id.rawValue),
            title: track.title,
            mediaType: .track,
            userData: track.userData,
            artistName: track.artistName,
            albumName: track.albumName,
            albumId: track.albumId.map { ItemID($0.rawValue) }
        )
        return modifier(MediaContextMenuModifier(item: item, artistId: track.artistId))
    }

    /// Attaches a context menu for an `Episode`, using the provided series
    /// context for "Go to Series" navigation.
    func mediaContextMenu(
        episode: Episode,
        seriesId: ItemID? = nil,
        seriesName: String? = nil
    ) -> some View {
        let item = MediaItem(
            id: ItemID(episode.id.rawValue),
            title: episode.title,
            overview: episode.overview,
            mediaType: .episode,
            runTimeTicks: episode.runtime.map { Int64($0 * 10_000_000) },
            userData: episode.userData,
            seriesName: seriesName,
            seriesId: seriesId,
            indexNumber: episode.episodeNumber,
            parentIndexNumber: episode.seasonNumber
        )
        return modifier(MediaContextMenuModifier(item: item, artistId: nil))
    }
}
