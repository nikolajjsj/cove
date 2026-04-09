import Defaults
import Foundation
import Networking

/// Provides read access to the active server credentials for app extensions.
///
/// Connection metadata (URL, user ID, server name, server ID) is read from the
/// shared ``Defaults`` suite. The auth token is read from the shared Keychain
/// via ``KeychainService`` using the App Group access group — it is never
/// stored in `UserDefaults`.
///
/// Both the main app and any extension share the same underlying storage:
/// - **Defaults keys** defined in ``Defaults.Keys`` (the `AppGroup` module)
/// - **Keychain** with access group ``AppGroupConstants/identifier``
public enum SharedCredentials {

    /// Keychain configured with the shared App Group access group.
    private static let keychain = KeychainService(
        accessGroup: AppGroupConstants.identifier
    )

    // MARK: - Connection Info (from shared Defaults)

    /// The active server's base URL.
    public static var serverURL: URL? {
        guard let string = Defaults[.activeServerURL] else { return nil }
        return URL(string: string)
    }

    /// The authenticated user's ID.
    public static var userId: String? {
        Defaults[.activeUserId]
    }

    /// The server's display name.
    public static var serverName: String? {
        Defaults[.activeServerName]
    }

    /// The active server connection's UUID string, used as the Keychain
    /// account to look up the auth token.
    public static var serverID: String? {
        Defaults[.activeServerID]
    }

    // MARK: - Auth Token (from shared Keychain)

    /// The authentication token retrieved from the shared Keychain.
    ///
    /// The token is stored by the main app's ``KeychainService`` using
    /// the App Group access group, making it readable by both the app
    /// and any extension without ever touching `UserDefaults`.
    public static var authToken: String? {
        guard let serverID else { return nil }
        return keychain.token(forServerID: serverID)
    }

    // MARK: - Availability

    /// Whether all required credentials are available for making API calls.
    public static var isAvailable: Bool {
        serverURL != nil && userId != nil && authToken != nil
    }
}
