import Foundation

/// The pages available in the full-screen audio player.
public enum PlayerPage: Int, CaseIterable, Sendable {
    /// Album artwork view.
    case artwork = 0
    /// Synced/unsynced lyrics view.
    case lyrics = 1
    /// Playback queue view.
    case queue = 2
}
