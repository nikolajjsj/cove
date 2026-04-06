import Defaults
import DownloadManager
import Foundation
import JellyfinProvider
import MediaServerKit
import Models
import Networking
import Persistence
import PlaybackEngine

@Observable
final class AppState {
    var isAuthenticated = false
    var isRestoringSession = true
    var activeConnection: ServerConnection?
    var libraries: [MediaLibrary] = []
    var isLoading = false
    var error: AppError?
    var isOffline = false

    let provider = JellyfinServerProvider()
    let audioPlayer = AudioPlaybackManager()
    let videoPlayerCoordinator = VideoPlayerCoordinator()
    let serverRepository: ServerRepository?
    let downloadManager: DownloadManagerService?
    let offlineSyncManager: OfflineSyncManager?
    let downloadRepository: DownloadRepository?
    let downloadGroupRepository: DownloadGroupRepository?
    let offlineMetadataRepository: OfflineMetadataRepository?
    let networkMonitor = NetworkMonitor.shared

    private let databaseManager: DatabaseManager?

    init() {
        // Try to set up persistence; if it fails, run without it
        if let dbManager = try? DatabaseManager(path: DatabaseManager.defaultPath) {
            self.databaseManager = dbManager
            self.serverRepository = ServerRepository(database: dbManager)

            let downloadRepo = DownloadRepository(database: dbManager)
            let reportRepo = OfflinePlaybackReportRepository(database: dbManager)
            let groupRepo = DownloadGroupRepository(database: dbManager)
            let metadataRepo = OfflineMetadataRepository(database: dbManager)

            self.downloadRepository = downloadRepo
            self.downloadGroupRepository = groupRepo
            self.offlineMetadataRepository = metadataRepo

            let manager = DownloadManagerService(
                downloadRepository: downloadRepo,
                reportRepository: reportRepo,
                groupRepository: groupRepo,
                metadataRepository: metadataRepo
            )

            // Wire up WiFi-only gate from user preference
            manager.isWifiOnlyEnabled = {
                Defaults[.downloadOverCellular] == false
            }

            self.downloadManager = manager
            self.offlineSyncManager = OfflineSyncManager(reportRepository: reportRepo)
        } else {
            self.databaseManager = nil
            self.serverRepository = nil
            self.downloadManager = nil
            self.offlineSyncManager = nil
            self.downloadRepository = nil
            self.downloadGroupRepository = nil
            self.offlineMetadataRepository = nil
        }

        // Start network monitoring
        networkMonitor.start()
        startNetworkObservation()
    }

    func restoreSession() async {
        defer { isRestoringSession = false }

        guard let repo = serverRepository else { return }

        // Restore incomplete downloads
        await downloadManager?.restoreDownloadsOnLaunch()

        do {
            let servers = try await repo.fetchAll()
            if let last = servers.last {
                if provider.restore(connection: last) {
                    activeConnection = last
                    isAuthenticated = true
                    wireUpPlayer()
                    await loadLibraries()

                    // Sync any pending offline playback reports
                    await syncOfflineReports()
                }
            }
        } catch {
            // Silently fail — user will see login screen
        }
    }

    func connect(url: URL, username: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let credentials = Credentials(username: username, password: password)
        let connection = try await provider.connect(url: url, credentials: credentials)

        // Persist the connection
        try? await serverRepository?.save(connection)

        activeConnection = connection
        isAuthenticated = true
        wireUpPlayer()
        await loadLibraries()
    }

    func loadLibraries() async {
        do {
            libraries = try await provider.libraries()
        } catch {
            libraries = []
        }
    }

    func disconnect() async {
        audioPlayer.stop()

        if let connection = activeConnection {
            try? await serverRepository?.delete(id: connection.id)
        }
        await provider.disconnect()
        activeConnection = nil
        libraries = []
        isAuthenticated = false
    }

    // MARK: - Download Helpers

    /// Resolve a download URL for a media item, save offline metadata & artwork, and enqueue it for download.
    func downloadItem(_ item: MediaItem, parentId: ItemID? = nil) async throws {
        guard let downloadManager, let connection = activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let serverId = connection.id.uuidString
        let remoteURL = try await provider.downloadURL(for: item, profile: nil)

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
            try? storage.prepareParentDirectory(
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
            artworkURL: artworkURL
        )
    }

    /// Download all episodes in a season. Saves metadata, artwork, and enqueues all episodes.
    func downloadSeason(
        series: MediaItem,
        season: Season,
        episodes: [Episode]
    ) async throws {
        guard let downloadManager, let connection = activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared

        // 1. Save and download artwork for the series (parent)
        var seriesMeta = OfflineMediaMetadata.from(item: series, serverId: serverId)
        try? storage.prepareParentDirectory(
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
        var episodeTuples: [(itemId: ItemID, title: String, remoteURL: URL)] = []

        for episode in episodes.sorted(by: { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) {
            // Save episode metadata
            var epMeta = OfflineMediaMetadata.from(
                episode: episode, seriesName: series.title, serverId: serverId
            )

            // Download episode thumbnail
            if let thumbURL = provider.imageURL(
                for: episode.id, type: .primary, maxSize: CGSize(width: 320, height: 180)
            ) {
                try? storage.prepareParentDirectory(
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

            // Resolve download URL for the episode
            let epItem = MediaItem(
                id: episode.id, title: episode.title, mediaType: .episode
            )
            let remoteURL = try await provider.downloadURL(for: epItem, profile: nil)
            episodeTuples.append((itemId: episode.id, title: episode.title, remoteURL: remoteURL))
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

    /// Download all tracks in an album. Saves metadata, artwork, and enqueues all tracks.
    func downloadAlbum(
        album: Album,
        tracks: [Track]
    ) async throws {
        guard let downloadManager, let connection = activeConnection,
            let metadataRepo = offlineMetadataRepository
        else { return }

        let serverId = connection.id.uuidString
        let storage = DownloadStorage.shared

        // 1. Save and download artwork for the album
        var albumMeta = OfflineMediaMetadata.from(album: album, serverId: serverId)
        try? storage.prepareParentDirectory(
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
        var trackTuples: [(itemId: ItemID, title: String, remoteURL: URL)] = []

        for track in tracks.sorted(by: {
            ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0)
        }) {
            let trackMeta = OfflineMediaMetadata.from(track: track, serverId: serverId)
            try await metadataRepo.save(trackMeta)

            // Resolve download URL
            let trackItem = MediaItem(id: track.id, title: track.title, mediaType: .track)
            let remoteURL = try await provider.downloadURL(for: trackItem, profile: nil)
            trackTuples.append((itemId: track.id, title: track.title, remoteURL: remoteURL))
        }

        // 3. Batch enqueue via download manager
        _ = try await downloadManager.enqueueAlbum(
            albumItemId: album.id,
            tracks: trackTuples,
            serverId: serverId,
            groupTitle: album.title
        )
    }

    /// Check if an item has been downloaded.
    func downloadState(for itemId: ItemID) async -> DownloadState? {
        guard let downloadManager, let connection = activeConnection else { return nil }
        let item = try? await downloadManager.download(
            for: itemId, serverId: connection.id.uuidString)
        return item?.state
    }

    /// Get the local file URL for an offline item, if available.
    func localFileURL(for itemId: ItemID) async -> URL? {
        guard let downloadManager, let connection = activeConnection else { return nil }
        guard
            let item = try? await downloadManager.download(
                for: itemId, serverId: connection.id.uuidString),
            item.state == .completed
        else {
            return nil
        }
        return downloadManager.localFileURL(for: item)
    }

    // MARK: - Offline Playback Report Queuing

    /// Queue a playback report for later sync when offline.
    func queueOfflinePlaybackReport(
        itemId: ItemID,
        positionTicks: Int64,
        eventType: PlaybackEventType
    ) async {
        guard let offlineSyncManager, let connection = activeConnection else { return }
        try? await offlineSyncManager.queuePlaybackEvent(
            itemId: itemId,
            serverId: connection.id.uuidString,
            positionTicks: positionTicks,
            eventType: eventType
        )
    }

    // MARK: - Player Wiring

    /// Configure the audio player's URL resolvers to use the current server provider.
    /// Called after a successful connection or session restore.
    private func wireUpPlayer() {
        // Use nonisolated(unsafe) because JellyfinServerProvider is thread-safe internally
        // (uses NSLock-protected state) but doesn't formally declare Sendable conformance.
        // These closures are only ever called from @MainActor context within AudioPlaybackManager.
        let provider = self.provider

        audioPlayer.streamURLResolver = { [weak self] track in
            // Try local file first (sync check via DownloadStorage)
            if let self,
                let connection = self.activeConnection
            {
                let storage = DownloadStorage.shared
                let dir = storage.itemDirectory(
                    serverId: connection.id.uuidString,
                    mediaType: .track,
                    itemId: track.id
                )
                let fm = FileManager.default
                if let contents = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil),
                    let mediaFile = contents.first(where: {
                        $0.lastPathComponent.hasPrefix("media.")
                    })
                {
                    return mediaFile
                }
            }
            // Fall back to remote stream
            return provider.audioStreamURL(for: track)
        }

        audioPlayer.artworkURLResolver = { [weak self] track in
            // Try local artwork first
            if let self,
                let connection = self.activeConnection,
                let albumId = track.albumId
            {
                let storage = DownloadStorage.shared
                let imageURL = storage.primaryImageURL(
                    serverId: connection.id.uuidString,
                    mediaType: .album,
                    itemId: albumId
                )
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    return imageURL
                }
            }
            // Fall back to remote
            guard let albumId = track.albumId else { return nil }
            return provider.imageURL(
                for: albumId,
                type: .primary,
                maxSize: CGSize(width: 600, height: 600)
            )
        }
    }

    // MARK: - Network Observation

    private func startNetworkObservation() {
        Task { [weak self] in
            for await connected in NetworkMonitor.shared.connectivityUpdates {
                guard let self else { break }
                await MainActor.run {
                    self.isOffline = !connected
                }

                // When coming back online, sync pending reports
                if connected {
                    await self.syncOfflineReports()
                }
            }
        }
    }

    // MARK: - Offline Sync

    private func syncOfflineReports() async {
        guard let offlineSyncManager, let connection = activeConnection else { return }
        guard networkMonitor.isConnected else { return }

        let provider = self.provider

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
}
