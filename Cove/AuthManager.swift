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
    }

    /// Disconnect from the current server and clear auth state.
    func disconnect() async {
        if let connection = activeConnection {
            try? await serverRepository?.delete(id: connection.id)
        }
        await provider.disconnect()
        activeConnection = nil
        isAuthenticated = false
    }
}
