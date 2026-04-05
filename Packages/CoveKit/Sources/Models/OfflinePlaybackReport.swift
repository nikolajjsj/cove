import Foundation

// MARK: - PlaybackEventType

/// The type of playback event being reported.
public enum PlaybackEventType: String, Codable, Sendable {
    /// Playback has started.
    case start
    /// Periodic progress update during playback.
    case progress
    /// Playback has stopped (paused, ended, or user navigated away).
    case stopped
}

// MARK: - OfflinePlaybackReport

/// A queued playback position report captured while offline.
///
/// When the device is offline, playback progress events are stored locally
/// and synced back to the server once connectivity is restored. Each report
/// captures a single point-in-time event (start, progress, or stopped) along
/// with the playback position in ticks.
public struct OfflinePlaybackReport: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this report (UUID string).
    public let id: String

    /// The media item this report is for.
    public let itemId: ItemID

    /// The server connection this report belongs to.
    public let serverId: String

    /// The playback position in ticks (1 tick = 100 nanoseconds, matching Jellyfin's format).
    public let positionTicks: Int64

    /// The type of playback event (start, progress, or stopped).
    public let eventType: PlaybackEventType

    /// When this playback event occurred on the device.
    public let timestamp: Date

    /// Whether this report has been successfully synced to the server.
    public let isSynced: Bool

    /// Creates a new offline playback report.
    /// - Parameters:
    ///   - id: Unique identifier for this report. Defaults to a new UUID string.
    ///   - itemId: The media item this report is for.
    ///   - serverId: The server connection UUID string.
    ///   - positionTicks: The playback position in ticks.
    ///   - eventType: The type of playback event.
    ///   - timestamp: When the event occurred. Defaults to now.
    ///   - isSynced: Whether this report has been synced. Defaults to `false`.
    public init(
        id: String = UUID().uuidString,
        itemId: ItemID,
        serverId: String,
        positionTicks: Int64,
        eventType: PlaybackEventType,
        timestamp: Date = Date(),
        isSynced: Bool = false
    ) {
        self.id = id
        self.itemId = itemId
        self.serverId = serverId
        self.positionTicks = positionTicks
        self.eventType = eventType
        self.timestamp = timestamp
        self.isSynced = isSynced
    }
}
