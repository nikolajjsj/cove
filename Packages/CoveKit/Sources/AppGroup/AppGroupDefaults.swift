import Defaults
import Foundation

/// The shared `UserDefaults` suite backed by the App Group container.
/// Both the main app and widget extension read/write through this suite.
///
/// Marked `nonisolated(unsafe)` because `UserDefaults` is not `Sendable`,
/// but the shared suite is effectively a singleton created once at launch.
public nonisolated(unsafe) let sharedSuite: UserDefaults = {
    guard let suite = UserDefaults(suiteName: AppGroupConstants.identifier) else {
        fatalError(
            "App Group '\(AppGroupConstants.identifier)' is not configured in the target's entitlements."
        )
    }
    return suite
}()

/// `Defaults` keys stored in the shared App Group suite.
///
/// These keys are the **single source of truth** for data shared between
/// the main app and any extensions (widgets, etc.). Both sides import
/// `AppGroup` and use `Defaults[.activeServerURL]`, etc.
///
/// - Note: The auth token is **not** stored here — it lives in the shared
///   Keychain via `KeychainService` with the App Group access group.
extension Defaults.Keys {

    /// The active server's base URL (e.g. `"https://jellyfin.example.com"`).
    public static let activeServerURL = Key<String?>(
        "activeServerURL",
        suite: sharedSuite
    )

    /// The authenticated user's ID on the active server.
    public static let activeUserId = Key<String?>(
        "activeUserId",
        suite: sharedSuite
    )

    /// The active server's human-readable display name.
    public static let activeServerName = Key<String?>(
        "activeServerName",
        suite: sharedSuite
    )

    /// The active server connection's UUID string.
    /// Used as the Keychain account key to look up the auth token.
    public static let activeServerID = Key<String?>(
        "activeServerID",
        suite: sharedSuite
    )
}
