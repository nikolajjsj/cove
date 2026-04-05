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
    let networkMonitor = NetworkMonitor.shared

    private let databaseManager: DatabaseManager?

    init() {
        // Try to set up persistence; if it fails, run without it
        if let dbManager = try? DatabaseManager(path: DatabaseManager.defaultPath) {
            self.databaseManager = dbManager
            self.serverRepository = ServerRepository(database: dbManager)

            let downloadRepo = DownloadRepository(database: dbManager)
            let reportRepo = OfflinePlaybackReportRepository(database: dbManager)

            self.downloadManager = DownloadManagerService(
                downloadRepository: downloadRepo,
                reportRepository: reportRepo
            )
            self.offlineSyncManager = OfflineSyncManager(reportRepository: reportRepo)
        } else {
            self.databaseManager = nil
            self.serverRepository = nil
            self.downloadManager = nil
            self.offlineSyncManager = nil
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

    /// Resolve a download URL for a media item and enqueue it for download.
    func downloadItem(_ item: MediaItem, parentId: ItemID? = nil) async throws {
        guard let downloadManager, let connection = activeConnection else { return }

        let remoteURL = try await provider.downloadURL(for: item, profile: nil)

        let artworkURL = provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 600, height: 600)
        )

        _ = try await downloadManager.enqueueDownload(
            itemId: item.id,
            serverId: connection.id.uuidString,
            title: item.title,
            mediaType: item.mediaType,
            remoteURL: remoteURL,
            parentId: parentId,
            artworkURL: artworkURL
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

        audioPlayer.streamURLResolver = { track in
            provider.audioStreamURL(for: track)
        }

        audioPlayer.artworkURLResolver = { track in
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
