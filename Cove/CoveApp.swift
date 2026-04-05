import ImageService
import SwiftUI

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
        }
    }
}
