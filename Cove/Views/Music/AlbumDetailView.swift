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
                        AlbumHeaderView(
                            albumItem: albumItem,
                            imageURL: albumImageURL,
                            artistName: inferredArtistName,
                            artistId: inferredArtistId,
                            metadata: metadataParts.joined(separator: " · "),
                            isOffline: isOffline
                        )
                        .padding(.bottom, 20)

                        AlbumActionButtons(
                            tracks: tracks,
                            albumId: albumItem.id,
                            onPlay: { playAllTracks(startingAt: 0) },
                            onShuffle: { playShuffled() }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 16)

                        // Album overview — shown only when online and overview exists
                        if !isOffline, let overview = albumItem.overview, !overview.isEmpty {
                            ExpandableOverview(text: overview, font: .subheadline)
                                .padding(.horizontal)
                        }

                        Divider()
                            .padding(.horizontal)

                        AlbumTrackListView(
                            tracks: tracks,
                            isOffline: isOffline,
                            onPlayTrack: { playAllTracks(startingAt: $0) },
                            onDeleteOfflineTrack: { track in await deleteOfflineTrack(track) }
                        )

                        // Similar Albums
                        if !isOffline {
                            Divider()
                                .padding(.horizontal)
                                .padding(.top, 24)

                            ContentRail(
                                title: "Similar Albums",
                                skeleton: { SkeletonCard.albumShelf(width: 140) }
                            ) {
                                try await authManager.provider.similarItems(
                                    for: albumItem, limit: nil)
                            } card: { item in
                                AlbumCard(
                                    item: item,
                                    subtitle: item.productionYear.map { String($0) },
                                    imageURL: authManager.provider.imageURL(
                                        for: item, type: .primary,
                                        maxSize: CGSize(width: 300, height: 300))
                                )
                                .frame(width: 140)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(albumItem.title)
        .inlineNavigationTitle()
        .toolbar {
            if !isOffline {
                ToolbarItem(placement: .primaryAction) {
                    FavoriteToggle(itemId: albumItem.id, userData: albumItem.userData)
                }
            }
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
                    AlbumDownloadButton(
                        isDownloadingAlbum: isDownloadingAlbum,
                        isAlbumDownloaded: isAlbumDownloaded,
                        tracksIsEmpty: tracks.isEmpty,
                        onRemove: { showRemoveConfirmation = true },
                        onDownload: { await downloadAlbum() }
                    )
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

    // MARK: - Playback

    private func playAllTracks(startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        let context = PlayContext(title: albumItem.title, type: .album, id: albumItem.id)
        appState.audioPlayer.play(tracks: tracks, startingAt: index, context: context)
    }

    private func playShuffled() {
        guard !tracks.isEmpty else { return }
        var shuffled = tracks
        shuffled.shuffle()
        let context = PlayContext(title: albumItem.title, type: .album, id: albumItem.id)
        appState.audioPlayer.play(tracks: shuffled, startingAt: 0, context: context)
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

    private var inferredArtistId: ItemID? {
        if let id = offlineAlbumMetadata?.artistId {
            return ItemID(id)
        }
        return tracks.first?.artistId.map { ItemID($0.rawValue) }
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
        guard let dm = downloadCoordinator.downloadManager else { return }
        for dl in offlineDownloads {
            try? await dm.deleteDownload(id: dl.id)
        }
        await loadTracks()
    }

    private func deleteOfflineTrack(_ track: Track) async {
        guard let dm = downloadCoordinator.downloadManager else { return }
        if let dl = offlineDownloads.first(where: { $0.itemId == track.id }) {
            try? await dm.deleteDownload(id: dl.id)
        }
        await loadTracks()
    }
}

// MARK: - Album Header View

private struct AlbumHeaderView: View {
    let albumItem: MediaItem
    let imageURL: URL?
    let artistName: String?
    let artistId: ItemID?
    let metadata: String
    let isOffline: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Album artwork
            MediaImage.artwork(url: imageURL, cornerRadius: 12)
                .frame(width: 280, height: 280)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            // Album title
            Text(albumItem.title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Artist name — navigates to the artist page once the ID is known
            if let artistName {
                if let artistId {
                    NavigationLink(
                        value: MediaItem(
                            id: artistId,
                            title: artistName,
                            mediaType: .artist
                        )
                    ) {
                        HStack(spacing: 4) {
                            Text(artistName)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(artistName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            // Metadata line: Year · Tracks · Duration
            if !metadata.isEmpty {
                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - Album Action Buttons

private struct AlbumActionButtons: View {
    let tracks: [Track]
    let albumId: ItemID
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 10) {
            // Primary actions
            HStack(spacing: 12) {
                Button {
                    onPlay()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(tracks.isEmpty)

                Button {
                    onShuffle()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(tracks.isEmpty)
            }

            // Secondary action
            Button {
                Task { await appState.startRadio(for: albumId) }
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(tracks.isEmpty)
        }
    }
}

// MARK: - Album Track List View

private struct AlbumTrackListView: View {
    let tracks: [Track]
    let isOffline: Bool
    let onPlayTrack: (Int) -> Void
    let onDeleteOfflineTrack: (Track) async -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(groupedByDisc.keys.sorted(), id: \.self) { discNumber in
                if let discTracks = groupedByDisc[discNumber] {
                    // Show disc header only if there are multiple discs
                    if groupedByDisc.count > 1 {
                        discHeader(discNumber)
                    }

                    ForEach(discTracks.enumerated(), id: \.element.id) { localIndex, track in
                        let globalIndex = globalTrackIndex(for: track)
                        let isFav =
                            appState.userDataStore?.isFavorite(
                                track.id, fallback: track.userData
                            ) ?? track.userData?.isFavorite ?? false
                        let row = AlbumTrackRow(
                            track: track,
                            isCurrentTrack: isCurrentTrack(track),
                            isPlaying: isCurrentTrack(track) && appState.audioPlayer.isPlaying,
                            isFavorite: isFav
                        ) {
                            onPlayTrack(globalIndex)
                        }

                        if isOffline {
                            row.contextMenu {
                                Button(role: .destructive) {
                                    Task { await onDeleteOfflineTrack(track) }
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

    private var groupedByDisc: [Int: [Track]] {
        Dictionary(grouping: tracks) { $0.discNumber ?? 1 }
    }

    private func globalTrackIndex(for track: Track) -> Int {
        tracks.firstIndex(where: { $0.id == track.id }) ?? 0
    }

    private func isCurrentTrack(_ track: Track) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id == track.id
    }
}

// MARK: - Album Download Button

private struct AlbumDownloadButton: View {
    let isDownloadingAlbum: Bool
    let isAlbumDownloaded: Bool
    let tracksIsEmpty: Bool
    let onRemove: () -> Void
    let onDownload: () async -> Void

    var body: some View {
        if isDownloadingAlbum {
            ProgressView()
        } else if isAlbumDownloaded {
            Button {
                onRemove()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        } else {
            Button {
                Task { await onDownload() }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
            }
            .disabled(tracksIsEmpty)
        }
    }
}

// MARK: - Track Row

private struct AlbumTrackRow: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    var isFavorite: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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

                if let label = qualityLabel {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 4))
                        // Optically align badge with the title baseline in .firstTextBaseline HStack
                        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
                }

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.caption)
                }

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

    /// Quality label shown for lossless formats.
    private var qualityLabel: String? {
        guard let codec = track.codec?.lowercased() else { return nil }
        let losslessCodecs: Set<String> = ["flac", "alac", "wav", "aiff", "ape", "wv", "truehd"]
        guard losslessCodecs.contains(codec) else { return nil }
        if let sampleRate = track.sampleRate, sampleRate > 44100 {
            return "Hi-Res"
        }
        return "Lossless"
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
