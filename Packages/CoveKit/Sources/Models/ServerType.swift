import Foundation

public enum ServerType: String, Codable, Sendable {
    case jellyfin
    // Future: .plex, .navidrome, .smb
}
