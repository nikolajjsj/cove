import DownloadManager
import Foundation
import JellyfinAPI
import JellyfinProvider
import MediaServerKit
import Models
import Persistence

@Observable
@MainActor
final class DownloadCoordinator {
    // MARK: - Services

    let downloadManager: DownloadManagerService?
    let offlineSyncManager: OfflineSyncManager?
    let downloadRepository: DownloadRepository?
    let downloadGroupRepository: DownloadGroupRepository?
    let offlineMetadataRepository: OfflineMetadataRepository?

    /// Reference to the auth manager for provider and connection access.
    /// Set after initialization to avoid circular init dependencies.
    weak var authManager: AuthManager?

    // MARK: - Init

    init(
        downloadManager: DownloadManagerService?,
        offlineSyncManager: OfflineSyncManager?,
        downloadRepository: DownloadRepository?,
        downloadGroupRepository: DownloadGroupRepository?,
        offlineMetadataRepository: OfflineMetadataRepository?
    ) {
        self.downloadManager = downloadManager
        self.offlineSyncManager = offlineSyncManager
        self.downloadRepository = downloadRepository
        self.downloadGroupRepository = downloadGroupRepository
        self.offlineMetadataRepository = offlineMetadataRepository
    }

    // MARK: - Artwork Helper

    /// Downloads primary artwork (and optionally a backdrop) for an item, saving paths into the metadata.
    private func downloadArtwork(
        for itemId: ItemID,
        mediaType: MediaType,
        serverId: String,
        provider: JellyfinServerProvider,
        storage: DownloadStorage,
        metadata: inout OfflineMediaMetadata,
        includeBackdrop: Bool = false
    ) async {
        let _ = try? storage.prepareParentDirectory(
            serverId: serverId, mediaType: mediaType, itemId: itemId
        )

        // Primary artwork
        if let primaryURL = provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 600, height: 600)
        ) {
            let dest = storage.primaryImageURL(
                serverId: serverId, mediaType: mediaType, itemId: itemId)
            if await storage.downloadImage(from: primaryURL, to: dest) {
                metadata.primaryImagePath = storage.relativePrimaryImagePath(
                    serverId: serverId, mediaType: mediaType, itemId: itemId
                )
            }
        }

        // Backdrop (for movies/series)
        if includeBackdrop {
            if let backdropURL = provider.imageURL(
                for: itemId, type: .backdrop, maxSize: CGSize(width: 1280, height: 720)
            ) {
                let dest = storage.backdropImageURL(
                    serverId: serverId, mediaType: mediaType, itemId: itemId)
                if await storage.downloadImage(from: backdropURL, to: dest) {
                    metadata.backdropImagePath = storage.relativeBackdropImagePath(
                        serverId: serverId, mediaType: mediaType, itemId: itemId
                    )
                }
            }
        }
    }

    // MARK: - Single Item Download

    func downloadItem(_ item: MediaItem, parentId: ItemID? = nil) async throws {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let provider = authManager.provider
        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared
        let downloadInfo = try await provider.downloadInfo(
            for: item, profile: provider.deviceProfile())
        let remoteURL = downloadInfo.url

        // Save offline metadata with artwork
        var metadata = OfflineMediaMetadata.from(item: item, serverId: serverId)
        let includeBackdrop = item.mediaType == .movie || item.mediaType == .series
        await downloadArtwork(
            for: item.id,
            mediaType: item.mediaType,
            serverId: serverId,
            provider: provider,
            storage: storage,
            metadata: &metadata,
            includeBackdrop: includeBackdrop
        )
        try await metadataRepo.save(metadata)

        let artworkURL = provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 600, height: 600)
        )

        _ = try await downloadManager.enqueueDownload(
            itemId: item.id,
            serverId: serverId,
            title: item.title,
            mediaType: item.mediaType,
            remoteURL: remoteURL,
            parentId: parentId,
            artworkURL: artworkURL,
            expectedBytes: downloadInfo.expectedBytes ?? 0
        )
    }

    // MARK: - Season Download

    func downloadSeason(
        series: MediaItem,
        season: Season,
        episodes: [Episode]
    ) async throws {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let provider = authManager.provider
        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared

        // 1. Save and download artwork for the series (parent)
        var seriesMeta = OfflineMediaMetadata.from(item: series, serverId: serverId)
        await downloadArtwork(
            for: series.id,
            mediaType: .series,
            serverId: serverId,
            provider: provider,
            storage: storage,
            metadata: &seriesMeta,
            includeBackdrop: true
        )
        try await metadataRepo.save(seriesMeta)

        // 2. Save season metadata
        let seasonMeta = OfflineMediaMetadata.from(season: season, serverId: serverId)
        try await metadataRepo.save(seasonMeta)

        // 3. Save episode metadata and resolve download URLs
        var episodeTuples: [(itemId: ItemID, title: String, remoteURL: URL, expectedBytes: Int64)] =
            []

        for episode in episodes.sorted(by: { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) {
            var epMeta = OfflineMediaMetadata.from(
                episode: episode, seriesName: series.title, serverId: serverId
            )
            await downloadArtwork(
                for: episode.id,
                mediaType: .episode,
                serverId: serverId,
                provider: provider,
                storage: storage,
                metadata: &epMeta
            )
            try await metadataRepo.save(epMeta)

            let epItem = MediaItem(
                id: episode.id, title: episode.title, mediaType: .episode
            )
            let downloadInfo = try await provider.downloadInfo(
                for: epItem, profile: provider.deviceProfile())
            episodeTuples.append(
                (
                    itemId: episode.id, title: episode.title, remoteURL: downloadInfo.url,
                    expectedBytes: downloadInfo.expectedBytes ?? 0
                ))
        }

        // 4. Batch enqueue via download manager
        let groupTitle = "\(series.title) – \(season.title)"
        _ = try await downloadManager.enqueueSeason(
            seasonItemId: season.id,
            seriesItemId: series.id,
            episodes: episodeTuples,
            serverId: serverId,
            groupTitle: groupTitle
        )
    }

    // MARK: - Album Download

    func downloadAlbum(
        album: Album,
        tracks: [Track]
    ) async throws {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let provider = authManager.provider
        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared

        // 1. Save and download artwork for the album
        var albumMeta = OfflineMediaMetadata.from(album: album, serverId: serverId)
        await downloadArtwork(
            for: album.id,
            mediaType: .album,
            serverId: serverId,
            provider: provider,
            storage: storage,
            metadata: &albumMeta
        )
        try await metadataRepo.save(albumMeta)

        // 2. Save track metadata and resolve download URLs
        var trackTuples: [(itemId: ItemID, title: String, remoteURL: URL, expectedBytes: Int64)] =
            []

        for track in tracks.sorted(by: {
            ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0)
        }) {
            let trackMeta = OfflineMediaMetadata.from(track: track, serverId: serverId)
            try await metadataRepo.save(trackMeta)

            let trackItem = MediaItem(id: track.id, title: track.title, mediaType: .track)
            let downloadInfo = try await provider.downloadInfo(
                for: trackItem, profile: provider.deviceProfile())
            trackTuples.append(
                (
                    itemId: track.id, title: track.title, remoteURL: downloadInfo.url,
                    expectedBytes: downloadInfo.expectedBytes ?? 0
                ))
        }

        // 3. Batch enqueue via download manager
        _ = try await downloadManager.enqueueAlbum(
            albumItemId: album.id,
            tracks: trackTuples,
            serverId: serverId,
            groupTitle: album.title
        )
    }

    // MARK: - Playlist Download

    func downloadPlaylist(
        playlist: Playlist,
        tracks: [Track]
    ) async throws {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let provider = authManager.provider
        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared

        // 1. Save and download artwork for the playlist
        var playlistMeta = OfflineMediaMetadata.from(playlist: playlist, serverId: serverId)
        await downloadArtwork(
            for: playlist.id,
            mediaType: .playlist,
            serverId: serverId,
            provider: provider,
            storage: storage,
            metadata: &playlistMeta
        )
        try await metadataRepo.save(playlistMeta)

        // 2. Save track metadata and resolve download URLs (preserve playlist order)
        var trackTuples: [(itemId: ItemID, title: String, remoteURL: URL, expectedBytes: Int64)] =
            []

        for track in tracks {
            let trackMeta = OfflineMediaMetadata.from(track: track, serverId: serverId)
            try await metadataRepo.save(trackMeta)

            let trackItem = MediaItem(id: track.id, title: track.title, mediaType: .track)
            let downloadInfo = try await provider.downloadInfo(
                for: trackItem, profile: provider.deviceProfile())
            trackTuples.append(
                (
                    itemId: track.id, title: track.title, remoteURL: downloadInfo.url,
                    expectedBytes: downloadInfo.expectedBytes ?? 0
                ))
        }

        // 3. Batch enqueue via download manager
        _ = try await downloadManager.enqueuePlaylist(
            playlistItemId: playlist.id,
            tracks: trackTuples,
            serverId: serverId,
            groupTitle: playlist.name
        )
    }

    // MARK: - Download State Queries

    func downloadState(for itemId: ItemID) async -> DownloadState? {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection
        else { return nil }
        let item = try? await downloadManager.download(
            for: itemId, serverId: connection.id.uuidString)
        return item?.state
    }

    func localFileURL(for itemId: ItemID) async -> URL? {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection
        else { return nil }
        guard
            let item = try? await downloadManager.download(
                for: itemId, serverId: connection.id.uuidString),
            item.state == .completed
        else {
            return nil
        }
        return downloadManager.localFileURL(for: item)
    }

    // MARK: - Offline Playback Reporting

    func queueOfflinePlaybackReport(
        itemId: ItemID,
        positionTicks: Int64,
        eventType: PlaybackEventType
    ) async {
        guard let offlineSyncManager, let authManager,
            let connection = authManager.activeConnection
        else { return }
        try? await offlineSyncManager.queuePlaybackEvent(
            itemId: itemId,
            serverId: connection.id.uuidString,
            positionTicks: positionTicks,
            eventType: eventType
        )
    }

    // MARK: - Offline Sync

    func syncOfflineReports() async {
        guard let offlineSyncManager, let authManager,
            let connection = authManager.activeConnection
        else { return }

        let provider = authManager.provider

        await offlineSyncManager.syncPendingReports(
            serverId: connection.id.uuidString
        ) { report in
            let item = MediaItem(
                id: report.itemId,
                title: "",
                mediaType: .movie  // Type doesn't matter for reporting
            )
            let position = JellyfinTicks.toSeconds(report.positionTicks)

            switch report.eventType {
            case .start:
                try await provider.reportPlaybackStart(item: item, position: position)
            case .progress:
                try await provider.reportPlaybackProgress(item: item, position: position)
            case .stopped:
                try await provider.reportPlaybackStopped(item: item, position: position)
            }
        }

        // Clean up old synced reports
        await offlineSyncManager.cleanup()
    }

    // MARK: - Restore on Launch

    func restoreDownloadsOnLaunch() async {
        await downloadManager?.restoreDownloadsOnLaunch()
    }
}
