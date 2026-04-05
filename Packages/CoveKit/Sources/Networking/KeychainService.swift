import Foundation
import Security

/// A thin wrapper around the iOS/macOS Keychain for storing auth tokens.
/// Tokens are keyed by server ID (UUID string).
public final class KeychainService: Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.nikolajjsj.jellyfin") {
        self.serviceName = serviceName
    }

    /// Store a token for the given server ID. Overwrites any existing value.
    public func setToken(_ token: String, forServerID serverID: String) throws {
        let data = Data(token.utf8)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status: status)
        }
    }

    /// Retrieve a token for the given server ID. Returns nil if not found.
    public func token(forServerID serverID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete the token for the given server ID.
    public func deleteToken(forServerID serverID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: serverID,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Delete all tokens stored by this service.
    public func deleteAllTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Keychain store failed with status: \(status)"
        case .unableToRetrieve(let status):
            return "Keychain retrieve failed with status: \(status)"
        }
    }
}
