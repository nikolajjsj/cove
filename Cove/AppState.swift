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

    /// `true` when the server could not be asked for its library list and nothing
    /// is saved locally either — a first launch with no connection. Once a list is
    /// saved this never flips again; the saved list is the library.
    var libraryLoadFailed = false

    /// `true` while a manual retry of `loadLibraries()` is in progress.
    var isRetryingLibraries = false

    // MARK: - User Data

    /// Centralized store for optimistic user data mutations (favorite, played, etc.).
    /// Set during app initialization in `CoveApp`.
    var userDataStore: UserDataStore?

    // MARK: - Local catalogue

    /// Set by `CoveApp` when the database opened. Every view reads from here and
    /// nowhere else; without a database the app shows its database error.
    var catalogRepository: CatalogRepository?
    /// Who the catalogue rows belong to. Nil until signed in.
    var catalogScope: CatalogRepository.Scope?
    /// The engine for the active connection. Recreated on every sign-in.
    var catalogSync: CatalogSyncEngine?
    /// Mirrors the engine's status on the main actor for views.
    var catalogSyncStatus: CatalogSyncStatus = .idle
    private var catalogStatusTask: Task<Void, Never>?

    /// Bumped every time a sync pass finishes or a library's first sync lands.
    /// Rails and grids re-query the catalogue on change, in place, so rows that
    /// arrive underneath the user appear without recreating the screen.
    var catalogGeneration = 0

    /// The catalogue for the signed-in user. Nil only when signed out or when the
    /// database failed to open.
    struct LocalCatalog {
        let repository: CatalogRepository
        let scope: CatalogRepository.Scope
    }

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
        .movies: NavigationPath(),
        .tvShows: NavigationPath(),
        .downloads: NavigationPath(),
        .settings: NavigationPath(),
    ]

    // MARK: - Services

    let authManager: AuthManager
    let downloadCoordinator: DownloadCoordinator
    let videoPlayerCoordinator = VideoPlayerCoordinator()
    let networkMonitor = NetworkMonitor.shared

    // MARK: - Init

    init(authManager: AuthManager, downloadCoordinator: DownloadCoordinator) {
        self.authManager = authManager
        self.downloadCoordinator = downloadCoordinator

        // Start network monitoring
        networkMonitor.start()
        startNetworkObservation()

        // The player resolves episodes through the catalogue, never the server.
        videoPlayerCoordinator.itemResolver = { [weak self] id in await self?.item(id: id) }
    }

    // MARK: - Session Lifecycle

    /// Restore a previous session and set up dependent services.
    func restoreSession() async {
        // Restore incomplete downloads
        await downloadCoordinator.restoreDownloadsOnLaunch()

        let success = await authManager.restoreSession()
        if success {
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
        await loadLibraries()
        startCatalogSync()
    }

    /// Everything the views read. One accessor, no conditions on sync progress:
    /// a half-synced library is still better than a spinner, and the missing
    /// rows arrive underneath the user as they browse.
    var catalog: LocalCatalog? {
        guard let repository = catalogRepository, let scope = catalogScope ?? currentCatalogScope else { return nil }
        return LocalCatalog(repository: repository, scope: scope)
    }

    /// Disconnect and tear down all state.
    func onDisconnect() async {
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

    /// The saved library list. The sync engine is the only thing that talks to
    /// the server about libraries; this just reads what it saved.
    func loadLibraries() async {
        guard let catalog else {
            libraries = []
            return
        }
        libraries = (try? await catalog.repository.libraries(scope: catalog.scope)) ?? []
        if !libraries.isEmpty { libraryLoadFailed = false }
    }

    /// The scope for the active connection, whether or not the engine exists yet.
    private var currentCatalogScope: CatalogRepository.Scope? {
        guard let connection = authManager.activeConnection else { return nil }
        return CatalogRepository.Scope(serverId: connection.id.uuidString, userId: connection.userId)
    }

    /// Whether a library's first sync has not finished yet — the grid says so
    /// instead of "This library is empty".
    func isBootstrapping(_ library: MediaLibrary) async -> Bool {
        guard let catalog else { return false }
        let key = "catalog:\(library.id.rawValue)"
        let state = try? await catalog.repository.syncState(scope: catalog.scope, key: key)
        return state.map { !$0.bootstrapComplete } ?? false
    }

    /// One page fetcher for every paged view. Views pass what varies — sort and
    /// filter — and never see a source.
    func pageFetcher(
        library: MediaLibrary,
        itemTypes: [String]?,
        sort: SortOptions,
        filter: @escaping @Sendable (_ limit: Int, _ startIndex: Int) -> FilterOptions
    ) -> PagedCollectionLoader<MediaItem>.PageFetcher {
        guard let catalog else { return { _, _ in .init(items: [], totalCount: 0) } }
        let libraryId = library.id.rawValue
        return { limit, startIndex in
            let result = try await catalog.repository.pagedItems(
                libraryId: libraryId, itemTypes: itemTypes, sort: sort,
                filter: filter(limit, startIndex), scope: catalog.scope)
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
                    let wasBusy = self.catalogSyncStatus.isBusy
                    let libraryFinished: Bool
                    if case .bootstrapping(let name, let done, let total) = status, total > 0, done >= total,
                        case .bootstrapping(let previousName, _, _) = self.catalogSyncStatus, previousName == name
                    {
                        libraryFinished = true
                    } else {
                        libraryFinished = false
                    }
                    self.catalogSyncStatus = status
                    // A pass ended, or one library's first sync landed: the rows
                    // changed under whatever is on screen.
                    if (wasBusy && !status.isBusy) || libraryFinished {
                        self.catalogGeneration += 1
                    }
                }
            }
        }
        guard let engine = catalogSync else { return }
        Task {
            // Outbox first, always: a sweep must never pull the server's stale
            // value over something the user just changed.
            await flushOutbox()
            // The library list is the first thing synced; the saved one stands
            // when the server is unreachable.
            do {
                _ = try await engine.refreshLibraries()
            } catch {
                if libraries.isEmpty { libraryLoadFailed = true }
            }
            let before = libraries
            await loadLibraries()
            if libraries != before { catalogGeneration += 1 }
            await engine.syncIfNeeded(libraries: catalogLibraries)
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

    /// Load an item's detail: the cached copy first, so the view fills instantly
    /// and works offline; the server only when there is no copy or the sync
    /// engine has seen the item change since (`cachedDetail.isStale`). User data
    /// always comes from the catalogue's user-data table, the outbox-protected
    /// truth, never from whatever the detail JSON happened to capture.
    func loadDetail(_ item: MediaItem, into loader: DetailItemLoader) async {
        guard let catalog, let engine = catalogSync else { return }
        let cached = try? await catalog.repository.cachedDetail(id: item.id.rawValue, scope: catalog.scope)
        if let cached { loader.apply(cached.item) }
        guard cached?.isStale ?? true, !isOffline else { return }
        await loader.load { try await engine.fetchDetail(itemId: item.id.rawValue) }
    }

    /// Resolve an item by id for deep links, the player and downloads: the cached
    /// detail, else the catalogue row, else — online only — a detail fetch.
    func item(id: ItemID) async -> MediaItem? {
        guard let catalog else { return nil }
        if let detail = try? await catalog.repository.detail(id: id.rawValue, scope: catalog.scope) {
            return detail
        }
        if let row = try? await catalog.repository.item(id: id.rawValue, scope: catalog.scope) {
            return row
        }
        guard !isOffline, let engine = catalogSync else { return nil }
        return try? await engine.fetchDetail(itemId: id.rawValue)
    }

    /// The full item for a download, pinned so eviction never strips a downloaded
    /// file of its metadata. Falls back to the catalogue row offline.
    func pinnedDetail(id: ItemID) async -> MediaItem? {
        guard let catalog else { return nil }
        if !isOffline, let engine = catalogSync,
            let fresh = try? await engine.fetchDetail(itemId: id.rawValue, pinned: true)
        {
            return fresh
        }
        if let detail = try? await catalog.repository.detail(id: id.rawValue, scope: catalog.scope) {
            try? await catalog.repository.setPinned(true, itemIds: [id.rawValue], scope: catalog.scope)
            return detail
        }
        return try? await catalog.repository.item(id: id.rawValue, scope: catalog.scope)
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

    /// The episode auto-play should queue after `item`, from the catalogue's
    /// ordering — so a downloaded season plays through offline.
    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard let catalog else { return nil }
        return try? await catalog.repository.nextEpisode(after: item.id.rawValue, scope: catalog.scope)
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

    /// Retry the library sync with visual feedback for the UI.
    func retryLoadLibraries() async {
        isRetryingLibraries = true
        if let engine = catalogSync {
            do {
                _ = try await engine.refreshLibraries()
                libraryLoadFailed = false
            } catch {
                if libraries.isEmpty { libraryLoadFailed = true }
            }
        }
        await loadLibraries()
        isRetryingLibraries = false
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

                    // A first launch that never reached the server: try the sync now.
                    if self.libraryLoadFailed {
                        self.startCatalogSync()
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
