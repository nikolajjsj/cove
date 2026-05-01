import Defaults
import DownloadManager
import Foundation
import JellyfinAPI
import JellyfinProvider
import MediaServerKit
import Models
import Persistence
import PlaybackEngine
import SwiftUI

@Observable
@MainActor
final class AppState {
    // MARK: - Library Data

    var libraries: [MediaLibrary] = []

    /// `true` when the last `loadLibraries()` call failed due to a network or server error.
    /// Used by the home view to distinguish "server has no libraries" from "couldn't connect."
    var libraryLoadFailed = false

    /// `true` while a manual retry of `loadLibraries()` is in progress.
    var isRetryingLibraries = false

    // MARK: - User Data

    /// Centralized store for optimistic user data mutations (favorite, played, etc.).
    /// Set during app initialization in `CoveApp`.
    var userDataStore: UserDataStore?

    // MARK: - UI State

    var isOffline = false
    var error: AppError?

    // MARK: - Navigation

    /// The currently selected tab in the app shell.
    var selectedTab: AppTab = .home

    /// Per-tab navigation paths for controlled NavigationStacks.
    /// Enables dismiss-then-navigate from the player and deep linking.
    var navigationPaths: [AppTab: NavigationPath] = [
        .home: NavigationPath(),
        .search: NavigationPath(),
        .music: NavigationPath(),
        .movies: NavigationPath(),
        .tvShows: NavigationPath(),
        .downloads: NavigationPath(),
        .settings: NavigationPath(),
    ]

    // MARK: - Services

    let authManager: AuthManager
    let downloadCoordinator: DownloadCoordinator
    let audioPlayer = AudioPlaybackManager()
    let videoPlayerCoordinator = VideoPlayerCoordinator()
    let networkMonitor = NetworkMonitor.shared

    // MARK: - Init

    init(authManager: AuthManager, downloadCoordinator: DownloadCoordinator) {
        self.authManager = authManager
        self.downloadCoordinator = downloadCoordinator

        // Start network monitoring
        networkMonitor.start()
        startNetworkObservation()
    }

    // MARK: - Session Lifecycle

    /// Restore a previous session and set up dependent services.
    func restoreSession() async {
        // Restore incomplete downloads
        await downloadCoordinator.restoreDownloadsOnLaunch()

        let success = await authManager.restoreSession()
        if success {
            wireUpPlayer()
            await loadLibraries()
            await downloadCoordinator.syncOfflineReports()

            // Clean up orphaned metadata and artwork that no longer have
            // corresponding download records (e.g. from interrupted deletions).
            if let connection = authManager.activeConnection {
                await downloadCoordinator.downloadManager?.cleanupOrphanedMetadata(
                    serverId: connection.id.uuidString)
            }
        }
    }

    /// Called after a successful connection to set up dependent services.
    func onConnected() async {
        wireUpPlayer()
        await loadLibraries()
    }

    /// Disconnect and tear down all state.
    func onDisconnect() async {
        audioPlayer.stop()
        libraries = []
        userDataStore?.invalidateAll()
        await authManager.disconnect()
    }

    // MARK: - Library Loading

    func loadLibraries() async {
        do {
            libraries = try await authManager.provider.libraries()
            libraryLoadFailed = false
        } catch {
            libraries = []
            libraryLoadFailed = true
        }
    }

    /// Retry loading libraries with visual feedback for the UI.
    func retryLoadLibraries() async {
        isRetryingLibraries = true
        await loadLibraries()
        isRetryingLibraries = false
    }

    // MARK: - Player Wiring

    /// Configure the audio player's URL resolvers and playback reporting callbacks
    /// to use the current server provider.
    /// Called after a successful connection or session restore.
    func wireUpPlayer() {
        let provider = authManager.provider
        let connection = authManager.activeConnection
        let coordinator = downloadCoordinator
        let networkMonitor = self.networkMonitor
        let userDataStore = self.userDataStore

        audioPlayer.streamURLResolver = { (track: Track) -> URL? in
            // Try local file first (sync check via DownloadStorage)
            if let connection {
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
            // Determine quality based on network type (expensive = cellular)
            let quality: AudioStreamingQuality =
                networkMonitor.isExpensive
                ? Defaults[.audioQualityCellular]
                : Defaults[.audioQualityWifi]
            // Fall back to remote stream with the selected quality
            return provider.audioStreamURL(for: track, maxBitRate: quality.maxBitRate)
        }

        audioPlayer.artworkURLResolver = { track in
            // Try local artwork first
            if let connection,
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
            let itemId = track.albumId ?? track.id
            return provider.imageURL(
                for: itemId,
                type: .primary,
                maxSize: CGSize(width: 600, height: 600)
            )
        }

        // MARK: Favourite state for the lock screen heart

        audioPlayer.favoriteStateProvider = { [weak self] track in
            guard let self else { return track.userData?.isFavorite ?? false }
            let itemId = ItemID(track.id.rawValue)
            return self.userDataStore?.isFavorite(itemId, fallback: track.userData)
                ?? track.userData?.isFavorite ?? false
        }

        audioPlayer.onToggleFavorite = { [weak self] track in
            guard let self else { return }
            let itemId = ItemID(track.id.rawValue)
            do {
                guard
                    let newValue = try await self.userDataStore?.toggleFavorite(
                        itemId: itemId,
                        current: track.userData
                    )
                else { return }
                // Keep the lock screen heart in sync after the toggle.
                self.audioPlayer.updateFavoriteState(isFavorite: newValue)
                ToastManager.shared.show(
                    newValue ? "Added to Favorites" : "Removed from Favorites",
                    icon: newValue ? "heart.fill" : "heart"
                )
            } catch {
                ToastManager.shared.show(
                    "Couldn't update favorite",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
            }
        }

        // MARK: Playback Reporting

        audioPlayer.onPlaybackStart = { track, position in
            let item = Self.mediaItem(from: track)
            if networkMonitor.isConnected {
                try? await provider.reportPlaybackStart(item: item, position: position)
            } else {
                let ticks = JellyfinTicks.fromSeconds(position)
                await coordinator.queueOfflinePlaybackReport(
                    itemId: item.id, positionTicks: ticks, eventType: .start)
            }
        }

        audioPlayer.onPlaybackProgress = { track, position, isPaused in
            let item = Self.mediaItem(from: track)
            if networkMonitor.isConnected {
                try? await provider.reportPlaybackProgress(
                    item: item, position: position, isPaused: isPaused)
            } else {
                let ticks = JellyfinTicks.fromSeconds(position)
                await coordinator.queueOfflinePlaybackReport(
                    itemId: item.id, positionTicks: ticks, eventType: .progress)
            }
        }

        audioPlayer.onPlaybackStopped = { track, position in
            let item = Self.mediaItem(from: track)
            if networkMonitor.isConnected {
                try? await provider.reportPlaybackStopped(item: item, position: position)
            } else {
                let ticks = JellyfinTicks.fromSeconds(position)
                await coordinator.queueOfflinePlaybackReport(
                    itemId: item.id, positionTicks: ticks, eventType: .stopped)
            }
        }

        audioPlayer.onTrackListened = { track in
            let itemId = ItemID(track.id.rawValue)
            try? await userDataStore?.markPlayed(itemId: itemId)
        }
    }

    /// Convert a `Track` to a `MediaItem` for playback reporting.
    private static func mediaItem(from track: Track) -> MediaItem {
        MediaItem(
            id: ItemID(track.id.rawValue),
            title: track.title,
            mediaType: .track,
            userData: track.userData,
            artistName: track.artistName,
            albumName: track.albumName,
            albumId: track.albumId.map { ItemID($0.rawValue) }
        )
    }

    // MARK: - Network Observation

    private func startNetworkObservation() {
        Task { [weak self] in
            for await connected in NetworkMonitor.shared.connectivityUpdates {
                guard let self else { break }
                self.isOffline = !connected

                // When coming back online, sync pending reports and retry failed loads
                if connected {
                    await self.downloadCoordinator.syncOfflineReports()

                    // Automatically retry loading libraries if the previous attempt failed
                    if self.libraryLoadFailed {
                        await self.loadLibraries()
                    }
                }
            }
        }
    }

    // MARK: - Navigation Helpers

    /// Navigate to a specific destination by switching tabs and appending to the navigation path.
    func navigate(to tab: AppTab, destination: any Hashable) {
        selectedTab = tab
        navigationPaths[tab, default: NavigationPath()].append(destination)
    }

    // MARK: - Common Media Actions

    /// Toggle the favorite state for any media item.
    ///
    /// Delegates to ``UserDataStore`` for optimistic updates and cross-view sync.
    /// Prefer using ``FavoriteToggle`` in new code — this method exists for
    /// backward compatibility during the migration.
    func toggleFavorite(itemId: ItemID, isFavorite: Bool) async {
        do {
            guard
                let newValue = try await userDataStore?.toggleFavorite(
                    itemId: itemId,
                    current: UserData(isFavorite: isFavorite)
                )
            else { return }
            ToastManager.shared.show(
                newValue ? "Added to Favorites" : "Removed from Favorites",
                icon: newValue ? "heart.fill" : "heart"
            )
            // If the toggled item is the currently playing track, sync the lock screen heart.
            if let currentTrack = audioPlayer.queue.currentTrack,
                ItemID(currentTrack.id.rawValue) == itemId
            {
                audioPlayer.updateFavoriteState(isFavorite: newValue)
            }
        } catch {
            ToastManager.shared.show(
                "Couldn't update favorite", icon: "exclamationmark.triangle", style: .error)
        }
    }

    /// Toggle the played/watched state for any media item.
    ///
    /// Delegates to ``UserDataStore`` for optimistic updates and cross-view sync.
    /// Prefer using ``PlayedToggle`` in new code — this method exists for
    /// backward compatibility during the migration.
    func togglePlayed(itemId: ItemID, isPlayed: Bool) async {
        do {
            guard
                let newValue = try await userDataStore?.togglePlayed(
                    itemId: itemId,
                    current: UserData(isPlayed: isPlayed)
                )
            else { return }
            ToastManager.shared.show(
                newValue ? "Marked as Watched" : "Marked as Unwatched",
                icon: newValue ? "eye.fill" : "eye.slash"
            )
        } catch {
            ToastManager.shared.show(
                "Couldn't update watched status", icon: "exclamationmark.triangle", style: .error)
        }
    }

    /// Start an instant-mix radio station seeded from any item.
    func startRadio(for itemId: ItemID) async {
        do {
            let tracks = try await authManager.provider.instantMix(for: itemId, limit: 50)
            guard !tracks.isEmpty else { return }
            audioPlayer.play(tracks: tracks, startingAt: 0)
            ToastManager.shared.show("Radio started", icon: "dot.radiowaves.left.and.right")
        } catch {
            ToastManager.shared.show(
                "Couldn't start radio", icon: "exclamationmark.triangle", style: .error)
        }
    }

    /// Queue an array of tracks to play next or at the end.
    func queueTracks(_ tracks: [Track], next: Bool) {
        guard !tracks.isEmpty else { return }
        for track in tracks {
            if next {
                audioPlayer.queue.addNext(track)
            } else {
                audioPlayer.queue.addToEnd(track)
            }
        }
        let message = next ? "Playing Next" : "Added to Up Next"
        let icon =
            next
            ? "text.line.first.and.arrowtriangle.forward"
            : "text.line.last.and.arrowtriangle.forward"
        ToastManager.shared.show(message, icon: icon)
    }
}

// MARK: - Preview Helpers

extension AppState {
    /// Creates an `AppState` with lightweight stub managers for SwiftUI previews.
    static var preview: AppState {
        let auth = AuthManager(serverRepository: nil)
        let downloads = DownloadCoordinator(
            downloadManager: nil,
            offlineSyncManager: nil,
            downloadRepository: nil,
            downloadGroupRepository: nil,
            offlineMetadataRepository: nil
        )
        downloads.authManager = auth
        let state = AppState(authManager: auth, downloadCoordinator: downloads)
        state.userDataStore = UserDataStore(provider: auth.provider)
        return state
    }

    /// The `AuthManager` used by this state — exposed for preview environment injection.
    static var previewAuthManager: AuthManager { preview.authManager }
}
