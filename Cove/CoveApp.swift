import Defaults
import DownloadManager
import ImageService
import JellyfinProvider
import Models
import Persistence
import SwiftUI
import UserNotifications

@main
struct CoveApp: App {
    @State private var authManager: AuthManager
    @State private var downloadCoordinator: DownloadCoordinator
    @State private var appState: AppState
    @State private var userDataStore: UserDataStore

    init() {
        ImageService.configure()

        // 1. Set up persistence layer
        let databaseManager = try? DatabaseManager(path: DatabaseManager.defaultPath)

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
                .task {
                    await requestNotificationPermissions()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
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

    private func requestNotificationPermissions() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
