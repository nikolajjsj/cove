import Foundation

/// Builds the `X-Emby-Authorization` header value required by Jellyfin.
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
            Host.current().localizedName ?? "Mac"
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
}
