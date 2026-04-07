import DownloadManager
import Foundation
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

    // MARK: - Single Item Download

    func downloadItem(_ item: MediaItem, parentId: ItemID? = nil) async throws {
        guard let downloadManager, let authManager,
            let connection = authManager.activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let provider = authManager.provider
        let serverId = connection.id.uuidString
        let downloadInfo = try await provider.downloadInfo(
            for: item, profile: provider.deviceProfile())
        let remoteURL = downloadInfo.url

        let artworkURL = provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 600, height: 600)
        )

        // Save offline metadata
        var metadata = OfflineMediaMetadata.from(item: item, serverId: serverId)

        // Download primary artwork
        let storage = DownloadStorage.shared
        if let artworkURL {
            let _ = try? storage.prepareParentDirectory(
                serverId: serverId, mediaType: item.mediaType, itemId: item.id
            )
            let destURL = storage.primaryImageURL(
                serverId: serverId, mediaType: item.mediaType, itemId: item.id
            )
            if await storage.downloadImage(from: artworkURL, to: destURL) {
                metadata.primaryImagePath = storage.relativePrimaryImagePath(
                    serverId: serverId, mediaType: item.mediaType, itemId: item.id
                )
            }
        }

        // Download backdrop for movies/series
        if item.mediaType == .movie || item.mediaType == .series {
            if let backdropURL = provider.imageURL(
                for: item, type: .backdrop, maxSize: CGSize(width: 1280, height: 720)
            ) {
                let destURL = storage.backdropImageURL(
                    serverId: serverId, mediaType: item.mediaType, itemId: item.id
                )
                if await storage.downloadImage(from: backdropURL, to: destURL) {
                    metadata.backdropImagePath = storage.relativeBackdropImagePath(
                        serverId: serverId, mediaType: item.mediaType, itemId: item.id
                    )
                }
            }
        }

        try await metadataRepo.save(metadata)

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
        let _ = try? storage.prepareParentDirectory(
            serverId: serverId, mediaType: .series, itemId: series.id
        )

        if let primaryURL = provider.imageURL(
            for: series, type: .primary, maxSize: CGSize(width: 600, height: 600)
        ) {
            let dest = storage.primaryImageURL(
                serverId: serverId, mediaType: .series, itemId: series.id)
            if await storage.downloadImage(from: primaryURL, to: dest) {
                seriesMeta.primaryImagePath = storage.relativePrimaryImagePath(
                    serverId: serverId, mediaType: .series, itemId: series.id
                )
            }
        }

        if let backdropURL = provider.imageURL(
            for: series, type: .backdrop, maxSize: CGSize(width: 1280, height: 720)
        ) {
            let dest = storage.backdropImageURL(
                serverId: serverId, mediaType: .series, itemId: series.id)
            if await storage.downloadImage(from: backdropURL, to: dest) {
                seriesMeta.backdropImagePath = storage.relativeBackdropImagePath(
                    serverId: serverId, mediaType: .series, itemId: series.id
                )
            }
        }

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

            if let thumbURL = provider.imageURL(
                for: episode.id, type: .primary, maxSize: CGSize(width: 320, height: 180)
            ) {
                let _ = try? storage.prepareParentDirectory(
                    serverId: serverId, mediaType: .episode, itemId: episode.id
                )
                let dest = storage.primaryImageURL(
                    serverId: serverId, mediaType: .episode, itemId: episode.id
                )
                if await storage.downloadImage(from: thumbURL, to: dest) {
                    epMeta.primaryImagePath = storage.relativePrimaryImagePath(
                        serverId: serverId, mediaType: .episode, itemId: episode.id
                    )
                }
            }

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
        let _ = try? storage.prepareParentDirectory(
            serverId: serverId, mediaType: .album, itemId: album.id
        )

        if let primaryURL = provider.imageURL(
            for: album.id, type: .primary, maxSize: CGSize(width: 600, height: 600)
        ) {
            let dest = storage.primaryImageURL(
                serverId: serverId, mediaType: .album, itemId: album.id)
            if await storage.downloadImage(from: primaryURL, to: dest) {
                albumMeta.primaryImagePath = storage.relativePrimaryImagePath(
                    serverId: serverId, mediaType: .album, itemId: album.id
                )
            }
        }

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
        let _ = try? storage.prepareParentDirectory(
            serverId: serverId, mediaType: .playlist, itemId: playlist.id
        )

        if let primaryURL = provider.imageURL(
            for: playlist.id, type: .primary, maxSize: CGSize(width: 600, height: 600)
        ) {
            let dest = storage.primaryImageURL(
                serverId: serverId, mediaType: .playlist, itemId: playlist.id)
            if await storage.downloadImage(from: primaryURL, to: dest) {
                playlistMeta.primaryImagePath = storage.relativePrimaryImagePath(
                    serverId: serverId, mediaType: .playlist, itemId: playlist.id
                )
            }
        }

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
            let position = TimeInterval(report.positionTicks) / 10_000_000.0

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
