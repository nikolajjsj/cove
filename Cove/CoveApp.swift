import ImageService
import SwiftUI
import UserNotifications

@main
struct CoveApp: App {
    @State private var appState = AppState()

    init() {
        ImageService.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    await requestNotificationPermissions()
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
