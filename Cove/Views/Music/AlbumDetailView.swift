import DownloadManager
import JellyfinProvider
import MediaServerKit
import Models
import Persistence
import PlaybackEngine
import SwiftUI

struct AlbumDetailView: View {
    let albumItem: MediaItem
    /// When non-nil, the view operates in offline mode using local storage.
    private let offlineServerId: String?

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDownloadingAlbum = false
    @State private var isAlbumDownloaded = false
    @State private var downloadError: String?
    @State private var showDownloadError = false
    @State private var showRemoveConfirmation = false

    // Offline-specific state
    @State private var offlineAlbumMetadata: OfflineMediaMetadata?
    @State private var showDeleteAlbumConfirmation = false
    @State private var trackToDelete: DownloadItem?
    @State private var offlineDownloads: [DownloadItem] = []

    // MARK: - Initializers

    /// Online init (unchanged API).
    init(albumItem: MediaItem) {
        self.albumItem = albumItem
        self.offlineServerId = nil
    }

    /// Offline init for use from DownloadsView.
    init(offlineAlbumId: String, serverId: String, title: String) {
        self.albumItem = MediaItem(id: ItemID(offlineAlbumId), title: title, mediaType: .album)
        self.offlineServerId = serverId
    }

    private var isOffline: Bool { offlineServerId != nil }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading album…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Album",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        albumHeader
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
        .navigationTitle(albumItem.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                if isOffline {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAlbumConfirmation = true
                        } label: {
                            Label("Remove Album", systemImage: "trash")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                } else if downloadCoordinator.downloadManager != nil {
                    albumDownloadButton
                }
            }
        }
        .alert("Download Error", isPresented: $showDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let downloadError {
                Text(downloadError)
            }
        }
        .confirmationDialog(
            "Remove \(albumItem.title)?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All Tracks", role: .destructive) {
                Task { await removeAlbumDownload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All downloaded tracks will be removed from your device.")
        }
        .confirmationDialog(
            "Remove \(albumItem.title)?",
            isPresented: $showDeleteAlbumConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All Tracks", role: .destructive) {
                Task { await deleteOfflineAlbum() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(tracks.count) tracks will be removed from your device.")
        }
        .task {
            await loadTracks()
            if !isOffline {
                await checkAlbumDownloadState()
            }
        }
    }

    // MARK: - Album Header

    private var albumHeader: some View {
        VStack(spacing: 16) {
            // Album artwork
            MediaImage.artwork(url: albumImageURL, cornerRadius: 12)
                .frame(width: 280, height: 280)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            // Album title
            Text(albumItem.title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Artist name
            if let artistName = inferredArtistName {
                Text(artistName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Metadata line: Year • Genre • Tracks • Duration
            albumMetadata
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var albumMetadata: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []

        if let year = offlineAlbumMetadata?.productionYear ?? albumItem.productionYear {
            parts.append(String(year))
        }

        if !tracks.isEmpty {
            let count = tracks.count
            parts.append("\(count) \(count == 1 ? "track" : "tracks")")
        }

        let totalDuration = tracks.compactMap(\.duration).reduce(0, +)
        if totalDuration > 0 {
            parts.append(TimeFormatting.longDuration(totalDuration))
        }

        return parts
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
            ForEach(groupedByDisc.keys.sorted(), id: \.self) { discNumber in
                if let discTracks = groupedByDisc[discNumber] {
                    // Show disc header only if there are multiple discs
                    if groupedByDisc.count > 1 {
                        discHeader(discNumber)
                    }

                    ForEach(discTracks.enumerated(), id: \.element.id) { localIndex, track in
                        let globalIndex = globalTrackIndex(for: track)
                        let row = AlbumTrackRow(
                            track: track,
                            isCurrentTrack: isCurrentTrack(track),
                            isPlaying: isCurrentTrack(track) && appState.audioPlayer.isPlaying
                        ) {
                            playAllTracks(startingAt: globalIndex)
                        }

                        if isOffline {
                            row.contextMenu {
                                Button(role: .destructive) {
                                    Task { await deleteOfflineTrack(track) }
                                } label: {
                                    Label("Remove Download", systemImage: "trash")
                                }
                            }
                        } else {
                            row.mediaContextMenu(track: track)
                        }

                        if localIndex < discTracks.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func discHeader(_ discNumber: Int) -> some View {
        HStack {
            Image(systemName: "opticaldisc")
                .foregroundStyle(.secondary)
            Text("Disc \(discNumber)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Disc Grouping

    private var groupedByDisc: [Int: [Track]] {
        Dictionary(grouping: tracks) { $0.discNumber ?? 1 }
    }

    private func globalTrackIndex(for track: Track) -> Int {
        tracks.firstIndex(where: { $0.id == track.id }) ?? 0
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

    // MARK: - Data Loading

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil

        if let serverId = offlineServerId {
            await loadOfflineTracks(serverId: serverId)
        } else {
            do {
                tracks = try await authManager.provider.tracks(album: albumItem.id)
            } catch {
                errorMessage = error.localizedDescription
                tracks = []
            }
        }
        isLoading = false
    }

    private func loadOfflineTracks(serverId: String) async {
        guard let metadataRepo = downloadCoordinator.offlineMetadataRepository,
            let dm = downloadCoordinator.downloadManager
        else { return }

        // Load album metadata for artist name, year, etc.
        offlineAlbumMetadata = try? await metadataRepo.fetch(
            itemId: albumItem.id.rawValue, serverId: serverId
        )

        // Load track metadata for this album
        let allTrackMeta =
            (try? await metadataRepo.fetchAll(
                serverId: serverId, mediaType: MediaType.track.rawValue
            )) ?? []
        let albumTrackMetas = allTrackMeta.filter { $0.albumId == albumItem.id.rawValue }

        // Load completed downloads for this album
        let allDownloads = (try? await dm.downloads(for: serverId)) ?? []
        offlineDownloads = allDownloads.filter { dl in
            dl.mediaType == .track
                && dl.state == .completed
                && (dl.parentId?.rawValue == albumItem.id.rawValue
                    || albumTrackMetas.contains { $0.itemId == dl.itemId.rawValue })
        }

        // Build Track objects from metadata (only for completed downloads)
        let completedIds = Set(offlineDownloads.map { $0.itemId.rawValue })
        tracks =
            albumTrackMetas
            .filter { completedIds.contains($0.itemId) }
            .map { meta in
                Track(
                    id: TrackID(meta.itemId),
                    title: meta.title ?? "Unknown Track",
                    albumId: meta.albumId.map { AlbumID($0) },
                    albumName: meta.albumName,
                    artistId: meta.artistId.map { ArtistID($0) },
                    artistName: meta.artistName,
                    trackNumber: meta.trackNumber,
                    discNumber: meta.discNumber,
                    duration: meta.duration,
                    codec: meta.codec
                )
            }
            .sorted(by: {
                ($0.discNumber ?? 1, $0.trackNumber ?? 0) < (
                    $1.discNumber ?? 1, $1.trackNumber ?? 0
                )
            })
    }

    // MARK: - Image Helpers

    private var albumImageURL: URL? {
        if offlineServerId != nil {
            if let path = offlineAlbumMetadata?.primaryImagePath {
                return DownloadStorage.shared.localImageURL(relativePath: path)
            }
            return nil
        }
        return authManager.provider.imageURL(
            for: albumItem,
            type: .primary,
            maxSize: CGSize(width: 600, height: 600)
        )
    }

    // MARK: - Inferred Metadata

    private var inferredArtistName: String? {
        offlineAlbumMetadata?.artistName ?? tracks.first?.artistName
    }

    // MARK: - Album Download (Online)

    @ViewBuilder
    private var albumDownloadButton: some View {
        if isDownloadingAlbum {
            ProgressView()
        } else if isAlbumDownloaded {
            Button {
                showRemoveConfirmation = true
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        } else {
            Button {
                Task { await downloadAlbum() }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(tracks.isEmpty)
        }
    }

    private func downloadAlbum() async {
        guard !tracks.isEmpty else { return }
        isDownloadingAlbum = true
        defer { isDownloadingAlbum = false }

        let album = Album(
            id: albumItem.id,
            title: albumItem.title,
            artistId: tracks.first?.artistId,
            artistName: tracks.first?.artistName,
            year: albumItem.productionYear,
            trackCount: tracks.count,
            duration: tracks.compactMap(\.duration).reduce(0, +)
        )

        do {
            try await downloadCoordinator.downloadAlbum(album: album, tracks: tracks)
            isAlbumDownloaded = true
        } catch {
            downloadError = "Failed to download album: \(error.localizedDescription)"
            showDownloadError = true
        }
    }

    private func removeAlbumDownload() async {
        guard let dm = downloadCoordinator.downloadManager,
            let connection = authManager.activeConnection
        else { return }
        let serverId = connection.id.uuidString
        let allDownloads = (try? await dm.downloads(for: serverId)) ?? []
        for dl in allDownloads where dl.mediaType == .track && dl.parentId == albumItem.id {
            try? await dm.deleteDownload(id: dl.id)
        }
        // Clean up metadata
        for track in tracks {
            try? await downloadCoordinator.offlineMetadataRepository?.delete(
                itemId: track.id.rawValue, serverId: serverId
            )
        }
        try? await downloadCoordinator.offlineMetadataRepository?.delete(
            itemId: albumItem.id.rawValue, serverId: serverId
        )
        isAlbumDownloaded = false
    }

    private func checkAlbumDownloadState() async {
        guard let dm = downloadCoordinator.downloadManager,
            let connection = authManager.activeConnection
        else { return }
        let serverId = connection.id.uuidString
        let allDownloads = (try? await dm.downloads(for: serverId)) ?? []
        let albumTracks = allDownloads.filter {
            $0.mediaType == .track && $0.parentId == albumItem.id
        }
        // Consider downloaded if there's at least one completed track for this album
        isAlbumDownloaded =
            !albumTracks.isEmpty && albumTracks.allSatisfy { $0.state == .completed }
    }

    // MARK: - Offline Deletion

    private func deleteOfflineAlbum() async {
        guard let dm = downloadCoordinator.downloadManager, let serverId = offlineServerId else {
            return
        }
        for dl in offlineDownloads {
            try? await dm.deleteDownload(id: dl.id)
        }
        for dl in offlineDownloads {
            try? await downloadCoordinator.offlineMetadataRepository?.delete(
                itemId: dl.itemId.rawValue, serverId: serverId
            )
        }
        try? await downloadCoordinator.offlineMetadataRepository?.delete(
            itemId: albumItem.id.rawValue, serverId: serverId
        )
        await loadTracks()
    }

    private func deleteOfflineTrack(_ track: Track) async {
        guard let dm = downloadCoordinator.downloadManager, let serverId = offlineServerId else {
            return
        }
        if let dl = offlineDownloads.first(where: { $0.itemId == track.id }) {
            try? await dm.deleteDownload(id: dl.id)
        }
        try? await downloadCoordinator.offlineMetadataRepository?.delete(
            itemId: track.id.rawValue, serverId: serverId
        )
        await loadTracks()
    }
}

// MARK: - Track Row

private struct AlbumTrackRow: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track number or now-playing indicator
                Group {
                    if isCurrentTrack {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    } else {
                        Text(trackNumberText)
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                    }
                }
                .frame(width: 28, alignment: .trailing)

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .foregroundStyle(isCurrentTrack ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if let artistName = track.artistName {
                        Text(artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Duration
                if let duration = track.duration, duration > 0 {
                    Text(TimeFormatting.trackTime(duration))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var trackNumberText: String {
        if let num = track.trackNumber {
            return "\(num)"
        }
        return ""
    }

}

// MARK: - Preview

#Preview {
    let state = AppState.preview
    NavigationStack {
        AlbumDetailView(
            albumItem: MediaItem(
                id: ItemID("preview-album"),
                title: "Preview Album",
                overview: "A great album",
                mediaType: .album
            )
        )
        .environment(state)
        .environment(state.authManager)
        .environment(state.downloadCoordinator)
    }
}
