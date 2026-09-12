import Foundation

/// Builds the `Authorization: MediaBrowser …` header value required by Jellyfin.
///
/// Jellyfin 12.0 disables the legacy authorization mechanisms (the
/// `X-Emby-Authorization` / `X-Emby-Token` headers and the `api_key` query
/// parameter) by default, so only the standard `Authorization` header and the
/// `ApiKey` query parameter are used here. Both are accepted by every server
/// from 10.8 through 12.x.
public enum JellyfinAuthHeader {
    /// The client name sent in auth headers.
    public static let clientName = "Cove"

    /// The device name (current device).
    public static var deviceName: String {
        #if os(iOS)
            "iPhone"
        #elseif os(tvOS)
            "Apple TV"
        #elseif os(macOS)
            ProcessInfo.processInfo.hostName
        #else
            "Apple Device"
        #endif
    }

    /// A stable device ID derived from the bundle identifier + a persisted UUID.
    public static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "cove_device_id") {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "cove_device_id")
        return newID
    }

    /// App version from the bundle.
    public static var clientVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Build the authorization header value.
    /// - Parameter token: The access token, if authenticated. Nil for pre-auth requests.
    /// - Returns: The full header value string.
    public static func headerValue(token: String? = nil) -> String {
        var parts = [
            "MediaBrowser Client=\"\(clientName)\"",
            "Device=\"\(deviceName)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(clientVersion)\"",
        ]
        if let token {
            parts.append("Token=\"\(token)\"")
        }
        return parts.joined(separator: ", ")
    }

    /// The header field name.
    public static let headerName = "Authorization"

    /// The query-parameter name used to authenticate requests that cannot carry
    /// headers — stream, download, and subtitle URLs handed to `AVPlayer` or
    /// `URLSession` background download tasks.
    ///
    /// Must be `ApiKey`, not the legacy `api_key`: Jellyfin 12.0 rejects the
    /// legacy spelling unless the server admin has re-enabled
    /// `EnableLegacyAuthorization`. `ApiKey` is read unconditionally by every
    /// server from 10.8 onwards.
    public static let apiKeyQueryName = "ApiKey"

    /// A ready-made `ApiKey` query item for the given token.
    public static func apiKeyQueryItem(token: String) -> URLQueryItem {
        URLQueryItem(name: apiKeyQueryName, value: token)
    }
}
