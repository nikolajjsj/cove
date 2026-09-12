import Defaults
import DownloadManager
import ImageService
import JellyfinProvider
import Models
import Persistence
import os
import SwiftUI

@main
struct CoveApp: App {
    @State private var authManager: AuthManager
    @State private var downloadCoordinator: DownloadCoordinator
    @State private var appState: AppState
    @State private var userDataStore: UserDataStore

    init() {
        ImageService.configure()

        // 1. Set up persistence layer
        //
        // Downloads, offline metadata, and saved servers all live here, so a
        // failure silently disables every offline feature. Record it so the UI
        // can tell the user instead of the app looking simply broken.
        let databaseManager: DatabaseManager?
        var databaseError: String?
        do {
            databaseManager = try DatabaseManager(path: DatabaseManager.defaultPath)
        } catch {
            databaseManager = nil
            databaseError = error.localizedDescription
            Logger(subsystem: AppConstants.bundleIdentifier, category: "Startup")
                .error("Database unavailable: \(error.localizedDescription)")
        }

        let serverRepository: ServerRepository? = databaseManager.map {
            ServerRepository(database: $0)
        }

        var downloadManagerService: DownloadManagerService?
        var offlineSyncManager: OfflineSyncManager?
        var downloadRepository: DownloadRepository?
        var downloadGroupRepository: DownloadGroupRepository?
        var offlineMetadataRepository: OfflineMetadataRepository?

        if let dbManager = databaseManager {
            let downloadRepo = DownloadRepository(database: dbManager)
            let reportRepo = OfflinePlaybackReportRepository(database: dbManager)
            let groupRepo = DownloadGroupRepository(database: dbManager)
            let metadataRepo = OfflineMetadataRepository(database: dbManager)

            downloadRepository = downloadRepo
            downloadGroupRepository = groupRepo
            offlineMetadataRepository = metadataRepo

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

            downloadManagerService = manager
            offlineSyncManager = OfflineSyncManager(reportRepository: reportRepo)
        }

        // 2. Create managers
        let authManager = AuthManager(serverRepository: serverRepository)

        // Download URLs are stored without credentials, so the engine reads the
        // live token per request. That also means a transfer resumed after a
        // re-login uses the new token instead of a stale one.
        let provider = authManager.provider
        downloadManagerService?.authTokenProvider = { provider.currentAccessToken }
        let downloadCoordinator = DownloadCoordinator(
            downloadManager: downloadManagerService,
            offlineSyncManager: offlineSyncManager,
            downloadRepository: downloadRepository,
            downloadGroupRepository: downloadGroupRepository,
            offlineMetadataRepository: offlineMetadataRepository
        )

        // Wire cross-references
        downloadCoordinator.authManager = authManager

        // 3. Create slim AppState with injected managers
        let appState = AppState(
            authManager: authManager,
            downloadCoordinator: downloadCoordinator
        )

        // 4. Create the centralized user data mutation store
        let userDataStore = UserDataStore(provider: authManager.provider)
        appState.userDataStore = userDataStore
        appState.videoPlayerCoordinator.userDataStore = userDataStore

        appState.databaseError = databaseError

        _authManager = State(initialValue: authManager)
        _downloadCoordinator = State(initialValue: downloadCoordinator)
        _appState = State(initialValue: appState)
        _userDataStore = State(initialValue: userDataStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(authManager)
                .environment(downloadCoordinator)
                .environment(userDataStore)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    #if DEBUG
                        await ScreenshotDriver.runIfRequested(
                            authManager: authManager,
                            appState: appState
                        )
                    #endif
                }
        }
    }

    /// Handles deep links from widgets and other sources.
    ///
    /// Supported URL schemes:
    /// - `cove://item/{itemId}` — navigates to the item's detail view.
    /// - `cove://play/{itemId}` — resolves the item and starts playback immediately.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "cove",
            let host = url.host(percentEncoded: false),
            let itemIdString = url.pathComponents.dropFirst().first
        else { return }

        let itemId = ItemID(itemIdString)

        Task {
            guard authManager.isAuthenticated else { return }
            do {
                let item = try await authManager.provider.item(id: itemId)
                switch host {
                case "play":
                    appState.videoPlayerCoordinator.play(
                        item: item,
                        using: authManager.provider
                    )
                case "item":
                    appState.selectedTab = .home
                    appState.navigationPaths[.home, default: NavigationPath()].append(item)
                default:
                    break
                }
            } catch {
                ToastManager.shared.show(
                    "Couldn't open item",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
            }
        }
    }

}
