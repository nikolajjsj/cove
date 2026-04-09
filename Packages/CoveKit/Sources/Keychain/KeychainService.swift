import Foundation
import Models
import Security

/// A thin wrapper around the iOS/macOS Keychain for storing auth tokens.
/// Tokens are keyed by server ID (UUID string).
///
/// When an `accessGroup` is provided (e.g. an App Group identifier like
/// `"group.com.nikolajjsj.cove"`), keychain items are stored in a shared
/// group accessible by both the main app and extensions (widgets, etc.).
public final class KeychainService: Sendable {
    private let serviceName: String
    private let accessGroup: String?

    /// Creates a new keychain service.
    ///
    /// - Parameters:
    ///   - serviceName: The `kSecAttrService` value used to scope stored items.
    ///   - accessGroup: An optional keychain access group (typically an App Group
    ///     identifier) that allows sharing items between the main app and extensions.
    ///     Pass `nil` to use the default (app-only) access group.
    public init(
        serviceName: String = AppConstants.bundleIdentifier,
        accessGroup: String? = nil
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    // MARK: - Base Query

    /// Builds the base query dictionary common to all operations.
    private func baseQuery(forServerID serverID: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    // MARK: - Store

    /// Store a token for the given server ID. Overwrites any existing value.
    public func setToken(_ token: String, forServerID serverID: String) throws {
        let data = Data(token.utf8)

        // Delete any existing item first
        let deleteQuery = baseQuery(forServerID: serverID)
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        var addQuery = baseQuery(forServerID: serverID)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status: status)
        }
    }

    // MARK: - Retrieve

    /// Retrieve a token for the given server ID. Returns nil if not found.
    ///
    /// When an `accessGroup` is configured, this first queries the shared
    /// group. If the token isn't found there, it falls back to querying
    /// without an access group (the app's default keychain slice) to
    /// transparently migrate tokens that were stored before shared-group
    /// support was added. On a successful fallback the token is re-stored
    /// in the shared group and the old ungrouped entry is deleted.
    public func token(forServerID serverID: String) -> String? {
        // 1. Try the shared access group first.
        if let token = rawToken(forServerID: serverID, accessGroup: accessGroup) {
            return token
        }

        // 2. If we have a shared group, try the legacy (ungrouped) location.
        guard let accessGroup, !accessGroup.isEmpty else { return nil }

        guard let legacyToken = rawToken(forServerID: serverID, accessGroup: nil) else {
            return nil
        }

        // 3. Migrate: store in the shared group, delete the old entry.
        try? setToken(legacyToken, forServerID: serverID)
        deleteLegacyToken(forServerID: serverID)

        return legacyToken
    }

    /// Low-level keychain fetch for a specific access group (or `nil` for ungrouped).
    private func rawToken(forServerID serverID: String, accessGroup: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes a token stored without an access group (legacy/pre-migration).
    private func deleteLegacyToken(forServerID serverID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Delete

    /// Delete the token for the given server ID.
    public func deleteToken(forServerID serverID: String) {
        let query = baseQuery(forServerID: serverID)
        SecItemDelete(query as CFDictionary)
    }

    /// Delete all tokens stored by this service.
    public func deleteAllTokens() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum KeychainError: Error, LocalizedError, Sendable {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            "Keychain store failed with status: \(status)"
        case .unableToRetrieve(let status):
            "Keychain retrieve failed with status: \(status)"
        }
    }
}
