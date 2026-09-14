import BackgroundTasks
import CatalogSync
import DataLoading
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

    // MARK: - Local catalogue

    /// Set by `CoveApp` when the database opened. Nil means no local catalogue:
    /// views fall back to the provider.
    var catalogRepository: CatalogRepository?
    /// Who the catalogue rows belong to. Nil until signed in.
    var catalogScope: CatalogRepository.Scope?
    /// The engine for the active connection. Recreated on every sign-in.
    var catalogSync: CatalogSyncEngine?
    /// Mirrors the engine's status on the main actor for views.
    var catalogSyncStatus: CatalogSyncStatus = .idle
    private var catalogStatusTask: Task<Void, Never>?

    /// The libraries the catalogue holds, in the engine's shape. Music is already
    /// gone from `libraries`; anything without a catalogue shape (playlists, home
    /// videos) stays on the provider.
    var catalogLibraries: [CatalogSyncEngine.Library] {
        libraries.compactMap { lib in
            CatalogSyncEngine.itemTypes(for: lib.collectionType).map {
                CatalogSyncEngine.Library(id: lib.id.rawValue, name: lib.name, itemTypes: $0)
            }
        }
    }

    // MARK: - UI State

    var isOffline = false
    var error: AppError?

    /// Set when the on-device database could not be opened at launch.
    ///
    /// Downloads, offline metadata, and saved servers all depend on it, so this
    /// is surfaced rather than leaving those features silently inert.
    var databaseError: String?

    // MARK: - Navigation

    /// The currently selected tab in the app shell.
    var selectedTab: AppTab = .home

    /// The shell layout that is currently active.
    ///
    /// Set by each shell view on appear so that ``navigate(to:destination:)`` can
    /// determine which tabs are actually rendered in the current environment and
    /// avoid silently swallowing navigations to tabs that don't exist in the tab bar.
    var shellLayout: AppTab.ShellLayout = .compact

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
    let lyricsStore = LyricsStore()
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
            startCatalogSync()
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
        startCatalogSync()
    }

    /// Disconnect and tear down all state.
    func onDisconnect() async {
        audioPlayer.stop()
        catalogStatusTask?.cancel()
        catalogStatusTask = nil
        catalogSync = nil
        catalogScope = nil
        catalogSyncStatus = .idle
        libraries = []
        userDataStore?.invalidateAll()
        await authManager.disconnect()
    }

    // MARK: - Library Loading

    func loadLibraries() async {
        do {
            let fetched = try await authManager.provider.libraries()
            // Dropping music here is what hides it everywhere else: the Music
            // tab, the Home rails and the Settings list are all derived from
            // this array. See FeatureFlags.musicEnabled.
            libraries = FeatureFlags.musicEnabled
                ? fetched
                : fetched.filter { $0.collectionType != .music }
            libraryLoadFailed = false
            // Persist only on success. An empty list on a 5xx is not "no libraries".
            if let repository = catalogRepository, let scope = currentCatalogScope {
                try? await repository.saveLibraries(libraries, scope: scope)
            }
        } catch {
            // Offline or unreachable: the saved list is the library. Without this
            // there is nothing to open even though every item is cached.
            if let repository = catalogRepository, let scope = currentCatalogScope,
                let saved = try? await repository.libraries(scope: scope), !saved.isEmpty
            {
                libraries = saved
                libraryLoadFailed = false
            } else {
                libraries = []
                libraryLoadFailed = true
            }
        }
    }

    /// The scope for the active connection, whether or not the engine exists yet.
    private var currentCatalogScope: CatalogRepository.Scope? {
        guard let connection = authManager.activeConnection else { return nil }
        return CatalogRepository.Scope(serverId: connection.id.uuidString, userId: connection.userId)
    }

    /// The local catalogue, if it can answer for this library right now.
    ///
    /// Three conditions, all required: the flag is on, a signed-in scope exists,
    /// and the library has finished bootstrapping *or* already holds rows — a
    /// half-bootstrapped library is still better than a spinner, and the missing
    /// rows arrive underneath the user as they browse.
    func localCatalog(for library: MediaLibrary)
        async -> (repository: CatalogRepository, scope: CatalogRepository.Scope)?
    {
        guard FeatureFlags.localCatalogEnabled,
            let repository = catalogRepository,
            let scope = catalogScope ?? currentCatalogScope,
            CatalogSyncEngine.itemTypes(for: library.collectionType) != nil
        else { return nil }
        let key = "catalog:\(library.id.rawValue)"
        guard let state = try? await repository.syncState(scope: scope, key: key) else { return nil }
        if state.bootstrapComplete { return (repository, scope) }
        let count = (try? await repository.count(libraryId: library.id.rawValue, scope: scope)) ?? 0
        return count > 0 ? (repository, scope) : nil
    }

    /// The local catalogue for scope-wide reads (Home, Search): available once any
    /// library has rows.
    func localCatalog() async -> (repository: CatalogRepository, scope: CatalogRepository.Scope)? {
        guard FeatureFlags.localCatalogEnabled,
            let repository = catalogRepository,
            let scope = catalogScope ?? currentCatalogScope
        else { return nil }
        let count = (try? await repository.count(scope: scope)) ?? 0
        return count > 0 ? (repository, scope) : nil
    }

    /// One page fetcher for every paged view: local catalogue when it can answer,
    /// the provider otherwise. Views pass what varies — sort and filter — and
    /// stop knowing which source answered.
    func pageFetcher(
        library: MediaLibrary,
        itemTypes: [String]?,
        sort: SortOptions,
        filter: @escaping @Sendable (_ limit: Int, _ startIndex: Int) -> FilterOptions
    ) async -> PagedCollectionLoader<MediaItem>.PageFetcher {
        let provider = authManager.provider
        if let local = await localCatalog(for: library) {
            let libraryId = library.id.rawValue
            return { limit, startIndex in
                let result = try await local.repository.pagedItems(
                    libraryId: libraryId, itemTypes: itemTypes, sort: sort,
                    filter: filter(limit, startIndex), scope: local.scope)
                return .init(items: result.items, totalCount: result.totalCount)
            }
        }
        return { limit, startIndex in
            let result = try await provider.pagedItems(in: library, sort: sort, filter: filter(limit, startIndex))
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Catalogue sync

    /// Build the engine for the active connection and run the first pass.
    ///
    /// Idempotent per connection: calling it again with the same engine alive just
    /// triggers another `syncIfNeeded`, which is what foregrounding wants.
    func startCatalogSync() {
        guard let repository = catalogRepository,
            let connection = authManager.activeConnection
        else { return }
        let scope = CatalogRepository.Scope(
            serverId: connection.id.uuidString, userId: connection.userId)
        userDataStore?.outboxScope = scope
        if catalogSync == nil || catalogScope != scope {
            catalogScope = scope
            let engine = CatalogSyncEngine(
                source: authManager.provider, repository: repository, scope: scope)
            catalogSync = engine
            catalogStatusTask?.cancel()
            catalogStatusTask = Task { [weak self] in
                for await status in await engine.statusStream {
                    guard let self, !Task.isCancelled else { return }
                    self.catalogSyncStatus = status
                }
            }
        }
        let libraries = catalogLibraries
        guard let engine = catalogSync else { return }
        Task {
            // Outbox first, always: a sweep must never pull the server's stale
            // value over something the user just changed.
            await flushOutbox()
            await engine.syncIfNeeded(libraries: libraries)
            await evictDetailCache()
        }
    }

    /// Send pending user-data edits to the server. Safe to call any time; a no-op
    /// when nothing is pending or nothing is signed in.
    func flushOutbox() async {
        guard let outbox = userDataStore?.outbox, let scope = catalogScope ?? currentCatalogScope,
            !isOffline
        else { return }
        let flusher = OutboxFlusher(outbox: outbox, writer: authManager.provider, scope: scope)
        await flusher.flush()
    }

    /// Edits waiting to reach the server — for the sign-out confirmation.
    func pendingOutboxCount() async -> Int {
        guard let outbox = userDataStore?.outbox, let scope = catalogScope ?? currentCatalogScope else { return 0 }
        return (try? await outbox.pendingCount(scope: scope)) ?? 0
    }

    /// Load an item's detail: cached first, so the view fills instantly and works
    /// offline; then the server, which refreshes the cache. User data always
    /// comes from the catalogue's user-data table, the outbox-protected truth,
    /// never from whatever the detail JSON happened to capture.
    func loadDetail(_ item: MediaItem, into loader: DetailItemLoader) async {
        let provider = authManager.provider
        let local = await localCatalog()
        if let local, let cached = try? await local.repository.detail(id: item.id.rawValue, scope: local.scope) {
            loader.apply(cached)
        }
        guard !isOffline else { return }
        await loader.load {
            var fresh = try await provider.item(id: item.id)
            if let local {
                try? await local.repository.saveDetail(fresh, scope: local.scope)
                if let ud = try? await local.repository.userData(itemId: item.id.rawValue, scope: local.scope) {
                    fresh.userData = ud
                }
            }
            return fresh
        }
    }

    /// Keep the detail cache under its soft cap. Pinned rows and anything with a
    /// live download are never touched; the repository enforces that by join.
    func evictDetailCache() async {
        guard let repository = catalogRepository, let scope = catalogScope ?? currentCatalogScope else { return }
        _ = try? await repository.evictDetails(budgetBytes: 200 * 1024 * 1024, scope: scope)
    }

    static let backgroundRefreshIdentifier = "com.nikolajjsj.cove.catalog-refresh"

    /// Ask for a refresh roughly a day out. iOS decides when, if at all; the
    /// foreground path covers everything this does, so nothing depends on it.
    func scheduleBackgroundRefresh() {
        guard authManager.isAuthenticated else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The daily pass: flush, bidirectional reconcile, full user-data sweep, evict.
    func performBackgroundRefresh() async {
        guard authManager.isAuthenticated, let engine = catalogSync else { return }
        await flushOutbox()
        await engine.reconcileAll(libraries: catalogLibraries)
        await evictDetailCache()
        scheduleBackgroundRefresh()
    }

    /// Foreground: pick up whatever changed while the app was away.
    func catalogForegrounded() {
        guard authManager.isAuthenticated else { return }
        startCatalogSync()
    }

    /// Pull-to-refresh: the full bidirectional reconcile, not just a delta.
    func refreshCatalog() async {
        guard let engine = catalogSync else { return }
        await engine.reconcileAll(libraries: catalogLibraries)
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

        // Session start/progress are live-session signals with no offline meaning;
        // the durable position goes through the user-data outbox on stop.
        audioPlayer.onPlaybackStart = { track, position in
            guard networkMonitor.isConnected else { return }
            let item = Self.mediaItem(from: track)
            try? await provider.reportPlaybackStart(item: item, position: position)
        }

        audioPlayer.onPlaybackProgress = { track, position, isPaused in
            guard networkMonitor.isConnected else { return }
            let item = Self.mediaItem(from: track)
            try? await provider.reportPlaybackProgress(
                item: item, position: position, isPaused: isPaused)
        }

        audioPlayer.onPlaybackStopped = { track, position in
            let item = Self.mediaItem(from: track)
            // The position lands locally either way; the outbox carries it if the
            // live report below cannot be sent.
            await userDataStore?.updatePlaybackPosition(
                itemId: item.id, position: position, runtime: item.runtime, currentData: track.userData)
            if networkMonitor.isConnected {
                try? await provider.reportPlaybackStopped(item: item, position: position)
            }
            // Offline: updatePlaybackPosition above already queued it in the outbox.
        }

        audioPlayer.onTrackListened = { track in
            let itemId = ItemID(track.id.rawValue)
            // Pass the track's server data so marking it played doesn't wipe its
            // favourite state out of the override.
            try? await userDataStore?.markPlayed(itemId: itemId, current: track.userData)
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
                    await self.flushOutbox()
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

    /// Navigate to a specific destination, switching to the target tab when it is rendered.
    ///
    /// On iPhone (compact layout) only one media tab is shown at a time, so the TV Shows tab
    /// may not be present even when the server has a TV Shows library. When this happens,
    /// blindly setting `selectedTab` has no visible effect and the navigation is silently lost.
    ///
    /// This method guards against that by checking whether the target tab actually exists in
    /// the current layout. If it does, the tab is switched and the destination is pushed as
    /// expected. If it does not, the destination is pushed onto the currently active tab so
    /// the user always ends up at the right place — just without a tab switch.
    func navigate(to tab: AppTab, destination: any Hashable) {
        let rendered = AppTab.availableTabs(for: self, layout: shellLayout)
        if rendered.contains(tab) {
            selectedTab = tab
            navigationPaths[tab, default: NavigationPath()].append(destination)
        } else {
            // Target tab is not in the current tab bar — push within the active tab.
            navigationPaths[selectedTab, default: NavigationPath()].append(destination)
        }
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
