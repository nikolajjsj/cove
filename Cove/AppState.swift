import Defaults
import DownloadManager
import Foundation
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
        } catch {
            libraries = []
        }
    }

    // MARK: - Player Wiring

    /// Configure the audio player's URL resolvers to use the current server provider.
    /// Called after a successful connection or session restore.
    func wireUpPlayer() {
        let provider = authManager.provider
        let connection = authManager.activeConnection

        audioPlayer.streamURLResolver = { track in
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
            // Fall back to remote stream
            return provider.audioStreamURL(for: track)
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
    }

    // MARK: - Network Observation

    private func startNetworkObservation() {
        Task { [weak self] in
            for await connected in NetworkMonitor.shared.connectivityUpdates {
                guard let self else { break }
                self.isOffline = !connected

                // When coming back online, sync pending reports
                if connected {
                    await self.downloadCoordinator.syncOfflineReports()
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
