import DownloadManager
import Foundation
import Models
import Persistence
import SwiftUI

/// View model for the redesigned Downloads page.
/// Uses GRDB `ValueObservation` for real-time updates from the download database.
@Observable
@MainActor
final class DownloadsViewModel {
    // MARK: - Published State

    /// All downloads for the active server, updated in real-time.
    private(set) var allDownloads: [DownloadItem] = []

    /// Offline metadata keyed by itemId for fast lookups.
    private(set) var metadataByItemId: [String: OfflineMediaMetadata] = [:]

    /// Download groups keyed by group ID.
    private(set) var groupsById: [String: DownloadGroup] = [:]

    var isLoading = true
    var errorMessage: String?

    // MARK: - Derived State

    /// Active downloads: downloading, queued, paused (sorted: downloading first, then queued, then paused).
    var activeDownloads: [DownloadItem] {
        allDownloads
            .filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
            .sorted { stateOrder($0.state) < stateOrder($1.state) }
    }

    /// Failed downloads.
    var failedDownloads: [DownloadItem] {
        allDownloads.filter { $0.state == .failed }
    }

    /// Whether the active+failed section should be visible.
    var hasInProgressOrFailed: Bool {
        !activeDownloads.isEmpty || !failedDownloads.isEmpty
    }

    /// Completed movie downloads.
    var completedMovies: [DownloadItem] {
        allDownloads.filter { $0.state == .completed && $0.mediaType == .movie }
    }

    /// Completed episode downloads, grouped by series.
    /// Returns an array of (seriesMetadata, episodes) tuples.
    var completedSeriesGroups: [(series: OfflineMediaMetadata, episodes: [DownloadItem])] {
        let episodes = allDownloads.filter { $0.state == .completed && $0.mediaType == .episode }

        // Group episodes by their parent series ID (from offline metadata)
        var seriesMap: [String: [DownloadItem]] = [:]

        for episode in episodes {
            let episodeMeta = metadataByItemId[episode.itemId.rawValue]
            let seriesId = episodeMeta?.seriesId ?? episode.parentId?.rawValue ?? "unknown"
            seriesMap[seriesId, default: []].append(episode)
        }

        // Build result with series metadata
        var result: [(series: OfflineMediaMetadata, episodes: [DownloadItem])] = []
        for (seriesId, eps) in seriesMap {
            if let seriesMeta = metadataByItemId[seriesId] {
                result.append((series: seriesMeta, episodes: eps))
            } else {
                // Fallback: create minimal metadata from available info
                let fallback = OfflineMediaMetadata(
                    itemId: seriesId,
                    serverId: serverId ?? "",
                    mediaType: MediaType.series.rawValue,
                    title: eps.first?.title ?? "Unknown Series"
                )
                result.append((series: fallback, episodes: eps))
            }
        }

        return result.sorted { ($0.series.title ?? "") < ($1.series.title ?? "") }
    }

    /// Completed track downloads, grouped by artist then album.
    /// Returns an array of (artistName, albums) where albums is [(albumMetadata, tracks)].
    var completedMusicByArtist:
        [(artist: String, albums: [(album: OfflineMediaMetadata, tracks: [DownloadItem])])]
    {
        let tracks = allDownloads.filter { $0.state == .completed && $0.mediaType == .track }

        // Group tracks by album
        var albumMap: [String: [DownloadItem]] = [:]
        for track in tracks {
            let trackMeta = metadataByItemId[track.itemId.rawValue]
            let albumId = trackMeta?.albumId ?? track.parentId?.rawValue ?? "unknown"
            albumMap[albumId, default: []].append(track)
        }

        // Group albums by artist
        var artistAlbums: [String: [(album: OfflineMediaMetadata, tracks: [DownloadItem])]] = [:]

        for (albumId, albumTracks) in albumMap {
            let albumMeta = metadataByItemId[albumId]
            let artistName = albumMeta?.artistName ?? "Unknown Artist"

            let meta =
                albumMeta
                ?? OfflineMediaMetadata(
                    itemId: albumId,
                    serverId: serverId ?? "",
                    mediaType: MediaType.album.rawValue,
                    title: albumTracks.first?.title ?? "Unknown Album"
                )

            artistAlbums[artistName, default: []].append((album: meta, tracks: albumTracks))
        }

        // Sort: artists alphabetically, albums by title
        return
            artistAlbums
            .map {
                (
                    artist: $0.key,
                    albums: $0.value.sorted { ($0.album.title ?? "") < ($1.album.title ?? "") }
                )
            }
            .sorted { $0.artist < $1.artist }
    }

    /// Whether there are any completed downloads at all.
    var hasCompletedContent: Bool {
        !completedMovies.isEmpty || !completedSeriesGroups.isEmpty
            || !completedMusicByArtist.isEmpty
    }

    /// Whether the entire downloads view is empty.
    var isEmpty: Bool {
        allDownloads.isEmpty
    }

    // MARK: - Dependencies

    private let downloadManager: DownloadManagerService
    private let metadataRepository: OfflineMetadataRepository?
    private let groupRepository: DownloadGroupRepository?
    private let downloadRepository: DownloadRepository?
    private var serverId: String?
    private var observationTask: Task<Void, Never>?

    // MARK: - Init

    init(
        downloadManager: DownloadManagerService,
        metadataRepository: OfflineMetadataRepository? = nil,
        groupRepository: DownloadGroupRepository? = nil,
        downloadRepository: DownloadRepository? = nil
    ) {
        self.downloadManager = downloadManager
        self.metadataRepository = metadataRepository
        self.groupRepository = groupRepository
        self.downloadRepository = downloadRepository
    }

    // MARK: - Lifecycle

    /// Start observing downloads for the given server.
    func startObserving(serverId: String) {
        self.serverId = serverId
        observationTask?.cancel()

        guard let downloadRepository else {
            // Fallback to polling if no repository available
            Task { await loadOnce(serverId: serverId) }
            return
        }

        observationTask = Task { [weak self] in
            for await downloads in downloadRepository.observeAll(serverId: serverId) {
                guard let self, !Task.isCancelled else { break }
                self.allDownloads = downloads
                self.isLoading = false

                // Refresh metadata when downloads change
                await self.loadMetadata(serverId: serverId)
                await self.loadGroups(serverId: serverId)
            }
        }
    }

    /// Stop observing.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Actions

    func pauseDownload(_ item: DownloadItem) async {
        try? await downloadManager.pauseDownload(id: item.id)
    }

    func resumeDownload(_ item: DownloadItem) async {
        try? await downloadManager.resumeDownload(id: item.id)
    }

    func retryDownload(_ item: DownloadItem) async {
        try? await downloadManager.retryDownload(id: item.id)
    }

    func deleteDownload(_ item: DownloadItem) async {
        try? await downloadManager.deleteDownload(id: item.id)
    }

    func deleteGroup(id: String) async {
        try? await downloadManager.deleteGroup(id: id)
        // The GRDB observation will automatically update the UI
    }

    /// Delete all downloaded episodes belonging to a series.
    func deleteSeriesEpisodes(seriesId: String) async {
        let episodes = allDownloads.filter { dl in
            dl.state == .completed
                && dl.mediaType == .episode
                && (dl.parentId?.rawValue == seriesId
                    || metadataByItemId[dl.itemId.rawValue]?.seriesId == seriesId)
        }

        // Collect unique group IDs to clean up
        let groupIds = Set(episodes.compactMap(\.groupId))
        let episodeIds = Set(episodes.map(\.id))

        for episode in episodes {
            try? await downloadManager.deleteDownload(id: episode.id)
        }

        // Clean up groups that are now empty
        for groupId in groupIds {
            let remaining = allDownloads.filter {
                $0.groupId == groupId && !episodeIds.contains($0.id)
            }
            if remaining.isEmpty {
                try? await downloadManager.deleteGroup(id: groupId)
            }
        }
    }

    /// Delete all downloaded tracks belonging to an album.
    func deleteAlbumTracks(albumId: String) async {
        let tracks = allDownloads.filter { dl in
            dl.state == .completed
                && dl.mediaType == .track
                && (dl.parentId?.rawValue == albumId
                    || metadataByItemId[dl.itemId.rawValue]?.albumId == albumId)
        }

        let groupIds = Set(tracks.compactMap(\.groupId))
        let trackIds = Set(tracks.map(\.id))

        for track in tracks {
            try? await downloadManager.deleteDownload(id: track.id)
        }

        for groupId in groupIds {
            let remaining = allDownloads.filter {
                $0.groupId == groupId && !trackIds.contains($0.id)
            }
            if remaining.isEmpty {
                try? await downloadManager.deleteGroup(id: groupId)
            }
        }
    }

    func deleteAllDownloads() async {
        guard let serverId else { return }
        try? await downloadManager.deleteAllDownloads(serverId: serverId)
    }

    func retryAllFailed() async {
        for item in failedDownloads {
            try? await downloadManager.retryDownload(id: item.id)
        }
    }

    // MARK: - Image URL Helpers

    /// Get a local image URL for an offline item, falling back to nil.
    func localPrimaryImageURL(for itemId: String) -> URL? {
        guard let meta = metadataByItemId[itemId],
            let path = meta.primaryImagePath
        else { return nil }
        return DownloadStorage.shared.localImageURL(relativePath: path)
    }

    func localBackdropImageURL(for itemId: String) -> URL? {
        guard let meta = metadataByItemId[itemId],
            let path = meta.backdropImagePath
        else { return nil }
        return DownloadStorage.shared.localImageURL(relativePath: path)
    }

    // MARK: - Private

    private func loadOnce(serverId: String) async {
        do {
            let all = try await downloadManager.allDownloads()
            allDownloads = all.filter { $0.serverId == serverId }
            await loadMetadata(serverId: serverId)
            await loadGroups(serverId: serverId)
        } catch {
            errorMessage = "Could not load downloads."
        }
        isLoading = false
    }

    private func loadMetadata(serverId: String) async {
        guard let metadataRepository else { return }
        do {
            let allMeta = try await metadataRepository.fetchAll(serverId: serverId)
            var map: [String: OfflineMediaMetadata] = [:]
            for meta in allMeta {
                map[meta.itemId] = meta
            }
            metadataByItemId = map
        } catch {
            // Non-critical — UI will show fallback text
        }
    }

    private func loadGroups(serverId: String) async {
        guard let groupRepository else { return }
        do {
            let groups = try await groupRepository.fetchAll(serverId: serverId)
            var map: [String: DownloadGroup] = [:]
            for group in groups {
                map[group.id] = group
            }
            groupsById = map
        } catch {
            // Non-critical
        }
    }

    private func stateOrder(_ state: DownloadState) -> Int {
        switch state {
        case .downloading: 0
        case .queued: 1
        case .paused: 2
        case .failed: 3
        case .completed: 4
        }
    }
}
