import Foundation

/// Represents a logical group of related downloads (e.g., all episodes in a season,
/// all tracks in an album). Used to display aggregate progress and manage batch operations.
public struct DownloadGroup: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this group (UUID string).
    public let id: String

    /// The parent item's Jellyfin ID (e.g., season ID, album ID).
    public let itemId: ItemID

    /// The server connection UUID string this group belongs to.
    public let serverId: String

    /// The type of the parent item (e.g., .season, .album).
    public let mediaType: MediaType

    /// Display title for the group (e.g., "Season 2", "Abbey Road").
    public let title: String

    /// Timestamp when the group was created.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        itemId: ItemID,
        serverId: String,
        mediaType: MediaType,
        title: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemId = itemId
        self.serverId = serverId
        self.mediaType = mediaType
        self.title = title
        self.createdAt = createdAt
    }
}

// MARK: - Derived State

extension DownloadGroup {
    /// Compute the aggregate state from a collection of child download items.
    ///
    /// Rules:
    /// - Any child downloading → `.downloading`
    /// - Any child queued (and none downloading) → `.queued`
    /// - Any child paused (and none active) → `.paused`
    /// - Any child failed (and none active/paused) → `.failed`
    /// - All completed → `.completed`
    public static func deriveState(from children: [DownloadItem]) -> DownloadState {
        guard !children.isEmpty else { return .queued }

        let states = Set(children.map(\.state))

        if states.contains(.downloading) { return .downloading }
        if states.contains(.queued) { return .queued }
        if states.contains(.paused) { return .paused }
        if states.contains(.failed) { return .failed }
        return .completed
    }

    /// Compute the aggregate progress from a collection of child download items.
    /// Returns the average progress across all children.
    public static func deriveProgress(from children: [DownloadItem]) -> Double {
        guard !children.isEmpty else { return 0 }
        let total = children.reduce(0.0) { $0 + $1.progress }
        return total / Double(children.count)
    }

    /// Compute total downloaded bytes from children.
    public static func deriveTotalBytes(from children: [DownloadItem]) -> Int64 {
        children.reduce(0) { $0 + $1.totalBytes }
    }

    /// Compute total downloaded bytes so far from children.
    public static func deriveDownloadedBytes(from children: [DownloadItem]) -> Int64 {
        children.reduce(0) { $0 + $1.downloadedBytes }
    }
}
