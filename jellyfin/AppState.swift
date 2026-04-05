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
    var activeConnection: ServerConnection?
    var libraries: [MediaLibrary] = []
    var isLoading = false
    var error: AppError?

    let provider = JellyfinServerProvider()
    let audioPlayer = AudioPlaybackManager()
    let serverRepository: ServerRepository?

    init() {
        // Try to set up persistence; if it fails, run without it
        if let dbManager = try? DatabaseManager(path: DatabaseManager.defaultPath) {
            self.serverRepository = ServerRepository(database: dbManager)
        } else {
            self.serverRepository = nil
        }
    }

    func restoreSession() async {
        guard let repo = serverRepository else { return }
        do {
            let servers = try await repo.fetchAll()
            if let last = servers.last {
                if provider.restore(connection: last) {
                    activeConnection = last
                    isAuthenticated = true
                    wireUpPlayer()
                    await loadLibraries()
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

    // MARK: - Player Wiring

    /// Configure the audio player's URL resolvers to use the current server provider.
    /// Called after a successful connection or session restore.
    private func wireUpPlayer() {
        // Use nonisolated(unsafe) because JellyfinServerProvider is thread-safe internally
        // (uses NSLock-protected state) but doesn't formally declare Sendable conformance.
        // These closures are only ever called from @MainActor context within AudioPlaybackManager.
        nonisolated(unsafe) let provider = self.provider

        audioPlayer.streamURLResolver = { track in
            provider.audioStreamURL(for: track)
        }

        audioPlayer.artworkURLResolver = { track in
            guard let albumId = track.albumId else { return nil }
            let item = MediaItem(id: albumId, title: "", mediaType: .album)
            return provider.imageURL(
                for: item,
                type: .primary,
                maxSize: CGSize(width: 600, height: 600)
            )
        }
    }
}
