import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    @State private var isDownloading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading playlist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Playlist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        playlistHeader
                            .padding(.bottom, 20)

                        actionButtons
                            .padding(.horizontal)
                            .padding(.bottom, 16)

                        Divider()
                            .padding(.horizontal)

                        trackList
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(playlist.name)
        .inlineNavigationTitle()
        .task {
            await loadTracks()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if downloadCoordinator.downloadManager != nil && !tracks.isEmpty {
                    Button {
                        downloadPlaylist()
                    } label: {
                        if isDownloading {
                            ProgressView()
                        } else {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameText = playlist.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
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
            "Delete \"\(playlist.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                Task { await deletePlaylist() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var playlistHeader: some View {
        VStack(spacing: 12) {
            MediaImage.artwork(url: playlistImageURL, cornerRadius: 12)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Text(playlist.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            playlistMetadata
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    private var playlistMetadata: some View {
        HStack(spacing: 6) {
            if let count = playlist.itemCount {
                Text("\(count) \(count == 1 ? "track" : "tracks")")
            }

            if playlist.itemCount != nil, playlist.duration != nil {
                Text("·")
            }

            if let duration = playlist.duration {
                Text(TimeFormatting.longDuration(duration))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        PlayShuffleButtons(
            isDisabled: tracks.isEmpty,
            onPlay: { playAllTracks(startingAt: 0) },
            onShuffle: { playShuffled() }
        )
    }

    // MARK: - Track List

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                TrackRow(
                    title: track.title,
                    subtitle: track.artistName,
                    imageURL: trackImageURL(for: track),
                    duration: track.duration,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isCurrentTrack(track) && appState.audioPlayer.isPlaying,
                    onTap: { playAllTracks(startingAt: index) }
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
                .mediaContextMenu(track: track)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await removeTrack(at: index) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if index < tracks.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Playback

    private func playAllTracks(startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func playShuffled() {
        guard !tracks.isEmpty else { return }
        var shuffled = tracks
        shuffled.shuffle()
        appState.audioPlayer.play(tracks: shuffled, startingAt: 0)
    }

    private func isCurrentTrack(_ track: Track) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id == track.id
    }

    // MARK: - Playlist Actions

    private func renamePlaylist() async {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        do {
            try await authManager.provider.renamePlaylist(playlist: playlist.id, name: newName)
            ToastManager.shared.show("Playlist renamed", icon: "pencil")
        } catch {
            ToastManager.shared.show(
                "Failed to rename playlist", icon: "exclamationmark.triangle", style: .error)
        }
    }

    private func deletePlaylist() async {
        do {
            try await authManager.provider.deletePlaylist(playlist: playlist.id)
            ToastManager.shared.show("Playlist deleted", icon: "trash")
            dismiss()
        } catch {
            ToastManager.shared.show(
                "Failed to delete playlist", icon: "exclamationmark.triangle", style: .error)
        }
    }

    private func removeTrack(at index: Int) async {
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]
        do {
            try await authManager.provider.removeFromPlaylist(
                playlist: playlist.id, entryIds: ["\(track.id)"]
            )
            tracks.remove(at: index)
            ToastManager.shared.show("Track removed", icon: "minus.circle")
        } catch {
            ToastManager.shared.show(
                "Failed to remove track", icon: "exclamationmark.triangle", style: .error)
        }
    }

    // MARK: - Data Loading

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            tracks = try await authManager.provider.playlistTracks(playlist: playlist.id)
        } catch {
            errorMessage = error.localizedDescription
            tracks = []
        }
        isLoading = false
    }

    // MARK: - Download

    private func downloadPlaylist() {
        Task {
            isDownloading = true
            try? await downloadCoordinator.downloadPlaylist(
                playlist: playlist, tracks: tracks)
            isDownloading = false
            ToastManager.shared.show("Downloading playlist", icon: "arrow.down.circle")
        }
    }

    // MARK: - Image Helpers

    private var playlistImageURL: URL? {
        authManager.provider.imageURL(
            for: playlist.id, type: .primary, maxSize: CGSize(width: 440, height: 440)
        )
    }

    private func trackImageURL(for track: Track) -> URL? {
        if let albumId = track.albumId {
            return authManager.provider.imageURL(
                for: albumId, type: .primary, maxSize: CGSize(width: 80, height: 80)
            )
        }
        return authManager.provider.imageURL(
            for: track.id, type: .primary, maxSize: CGSize(width: 80, height: 80)
        )
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        PlaylistDetailView(
            playlist: Playlist(
                id: PlaylistID("preview"),
                name: "My Playlist",
                itemCount: 10,
                duration: 3600
            )
        )
        .environment(state)
        .environment(state.authManager)
        .environment(state.downloadCoordinator)
    }
}
