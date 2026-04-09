import AppGroup
import Defaults
import Foundation
import JellyfinProvider
import MediaServerKit
import Models
import Persistence

@Observable
@MainActor
final class AuthManager {
    // MARK: - Observable State
    var isAuthenticated = false
    var isRestoringSession = true
    var isLoading = false
    var activeConnection: ServerConnection?

    // MARK: - Services
    let provider = JellyfinServerProvider()
    let serverRepository: ServerRepository?

    // MARK: - Init
    init(serverRepository: ServerRepository?) {
        self.serverRepository = serverRepository
    }

    // MARK: - Auth Flow

    /// Attempt to restore a previously saved session from the database.
    /// Returns `true` if a session was successfully restored.
    func restoreSession() async -> Bool {
        defer { isRestoringSession = false }

        guard let repo = serverRepository else { return false }

        do {
            let servers = try await repo.fetchAll()
            if let last = servers.last {
                if provider.restore(connection: last) {
                    activeConnection = last
                    isAuthenticated = true
                    syncConnectionToSharedDefaults()
                    return true
                }
            }
        } catch {
            // Silently fail — user will see login screen
        }
        return false
    }

    /// Connect to a server with the given credentials.
    func connect(url: URL, username: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let credentials = Credentials(username: username, password: password)
        let connection = try await provider.connect(url: url, credentials: credentials)

        // Persist the connection
        try? await serverRepository?.save(connection)

        activeConnection = connection
        isAuthenticated = true
        syncConnectionToSharedDefaults()
    }

    /// Disconnect from the current server and clear auth state.
    func disconnect() async {
        if let connection = activeConnection {
            try? await serverRepository?.delete(id: connection.id)
        }
        await provider.disconnect()
        activeConnection = nil
        isAuthenticated = false
        clearSharedDefaults()
    }

    // MARK: - Shared Defaults Sync

    /// Writes the active server connection info to the shared App Group
    /// `Defaults` suite so widget extensions can discover the server.
    ///
    /// Uses the keys defined in `AppGroup` so both the app and
    /// widget read/write the exact same `Defaults.Keys`.
    ///
    /// The auth token itself is stored in the shared Keychain (via the
    /// provider's `KeychainService` which uses the App Group access group),
    /// so it is never written to `UserDefaults`.
    private func syncConnectionToSharedDefaults() {
        guard let connection = activeConnection else { return }

        Defaults[.activeServerURL] = connection.url.absoluteString
        Defaults[.activeUserId] = connection.userId
        Defaults[.activeServerName] = connection.name
        Defaults[.activeServerID] = connection.id.uuidString
    }

    /// Clears widget-shared connection info from the App Group `Defaults` suite.
    private func clearSharedDefaults() {
        Defaults[.activeServerURL] = nil
        Defaults[.activeUserId] = nil
        Defaults[.activeServerName] = nil
        Defaults[.activeServerID] = nil
    }
}
