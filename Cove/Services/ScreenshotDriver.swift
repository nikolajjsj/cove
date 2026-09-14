#if DEBUG
import Foundation
import JellyfinProvider
import Models
import Persistence
import SwiftUI

/// Puts the app on a chosen screen for App Store capture.
///
/// Every screen worth showing sits behind a server login, and the simulator's
/// tap automation is not always available, so a capture script needs some way
/// in that does not involve touching the UI. Launch arguments of the form
/// `-key value` are parsed into `UserDefaults` by Foundation, which gives us
/// one for free:
///
///     xcrun simctl launch <device> com.nikolajjsj.cove \
///         -screenshotServer https://demo.jellyfin.org/stable \
///         -screenshotUser demo \
///         -screenshotTab movies
///
/// Pass a real server only when you are willing for its contents to end up in a
/// screenshot; point it at a demo instance otherwise. Compiled out of release
/// builds entirely.
enum ScreenshotDriver {
    private static let tabs: [String: AppTab] = [
        "home": .home, "search": .search, "movies": .movies,
        "tvShows": .tvShows, "downloads": .downloads, "settings": .settings,
    ]

    static func runIfRequested(authManager: AuthManager, appState: AppState) async {
        let defaults = UserDefaults.standard
        let wantsTab = defaults.string(forKey: "screenshotTab") != nil
        let wantsItem = defaults.string(forKey: "screenshotItem") != nil
        let server = defaults.string(forKey: "screenshotServer")
        guard server != nil || wantsTab || wantsItem else { return }

        // Session restore runs concurrently at launch. Deciding before it finishes
        // would sign in a second time and, before connection ids were reused, mint
        // a second server record for the same account.
        while authManager.isRestoringSession {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Tab / item selection alone is allowed without a server: it drives a
        // restored session, which is how an offline launch is exercised.
        if !authManager.isAuthenticated,
            let server, let url = URL(string: server),
            let username = defaults.string(forKey: "screenshotUser")
        {
            do {
                try await authManager.connect(
                    url: url,
                    username: username,
                    password: defaults.string(forKey: "screenshotPassword") ?? ""
                )
                await appState.onConnected()
            } catch {
                // Printed rather than surfaced: the capture script reads the log.
                print("[ScreenshotDriver] connect failed: \(error)")
                return
            }
        }

        if let name = defaults.string(forKey: "screenshotTab"), let tab = Self.tabs[name] {
            appState.selectedTab = tab
        }

        // Pushing in-process rather than through `cove://` on purpose: an
        // external open shows a system "Open in Cove?" alert, which lands in
        // the middle of the screenshot.
        if let rawId = defaults.string(forKey: "screenshotItem") {
            // The catalogue first, exactly as a tap on a grid cell would: that is
            // what makes an offline launch reach a detail screen at all.
            var item: MediaItem?
            if let repository = appState.catalogRepository,
                let connection = authManager.activeConnection
            {
                // Derive the scope from the connection rather than waiting on the
                // engine to publish one; right after restore the latter may not
                // exist yet, and the item does.
                let scope = CatalogRepository.Scope(
                    serverId: connection.id.uuidString, userId: connection.userId)
                item = try? await repository.item(id: rawId, scope: scope)
            }
            if item == nil {
                item = try? await authManager.provider.item(id: ItemID(rawId))
            }
            if let item {
                appState.selectedTab = .home
                appState.navigationPaths[.home, default: NavigationPath()].append(item)
            } else {
                print("[ScreenshotDriver] item \(rawId) not found locally or remotely")
            }
        }
    }
}
#endif
