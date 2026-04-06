import Foundation

/// Represents a media item that has been queued or completed for offline download.
///
/// Each `DownloadItem` tracks the full lifecycle of a download — from initial queue entry
/// through active downloading to completion or failure. It stores all the metadata needed
/// to display download status in the UI and to resume or retry downloads.
public struct DownloadItem: Identifiable, Codable, Hashable, Sendable {

    /// Unique identifier for this download (UUID string).
    public let id: String

    /// The media item identifier on the server.
    public let itemId: ItemID

    /// The server connection UUID string this download belongs to.
    public let serverId: String

    /// Display title for the downloaded item.
    public let title: String

    /// The type of media being downloaded.
    public let mediaType: MediaType

    /// Current state of the download.
    public let state: DownloadState

    /// Download progress as a fraction from 0.0 to 1.0.
    public let progress: Double

    /// Total size of the file in bytes, as reported by the server.
    public let totalBytes: Int64

    /// Number of bytes downloaded so far.
    public let downloadedBytes: Int64

    /// Relative path to the downloaded file under the app's downloads directory.
    /// `nil` until the download completes successfully.
    public let localFilePath: String?

    /// The remote URL the file is being downloaded from.
    public let remoteURL: String

    /// Optional parent item identifier (e.g. album ID for tracks, series ID for episodes).
    /// Used for grouping downloads in the UI.
    public let parentId: ItemID?

    /// Optional group identifier linking this download to a `DownloadGroup`.
    /// Used when downloading entire seasons or albums.
    public let groupId: String?

    /// URL string for cached artwork associated with this item.
    public let artworkURL: String?

    /// Human-readable error message when `state` is `.failed`.
    public let errorMessage: String?

    /// Timestamp when the download was first created / queued.
    public let createdAt: Date

    /// Timestamp when the download completed successfully. `nil` if not yet completed.
    public let completedAt: Date?

    /// Creates a new `DownloadItem` with all fields specified.
    ///
    /// - Parameters:
    ///   - id: Unique download identifier (UUID string).
    ///   - itemId: The media item identifier on the server.
    ///   - serverId: The server connection UUID string.
    ///   - title: Display title for the download.
    ///   - mediaType: The type of media being downloaded.
    ///   - state: Current download state.
    ///   - progress: Download progress from 0.0 to 1.0.
    ///   - totalBytes: Total expected file size in bytes.
    ///   - downloadedBytes: Bytes downloaded so far.
    ///   - localFilePath: Relative path to the local file, or `nil`.
    ///   - remoteURL: The remote URL to download from.
    ///   - parentId: Optional parent item identifier for grouping.
    ///   - groupId: Optional group identifier linking to a `DownloadGroup`.
    ///   - artworkURL: Optional artwork URL string.
    ///   - errorMessage: Optional error description on failure.
    ///   - createdAt: When the download was queued.
    ///   - completedAt: When the download finished, or `nil`.
    public init(
        id: String,
        itemId: ItemID,
        serverId: String,
        title: String,
        mediaType: MediaType,
        state: DownloadState,
        progress: Double,
        totalBytes: Int64,
        downloadedBytes: Int64,
        localFilePath: String?,
        remoteURL: String,
        parentId: ItemID?,
        groupId: String? = nil,
        artworkURL: String?,
        errorMessage: String?,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.itemId = itemId
        self.serverId = serverId
        self.title = title
        self.mediaType = mediaType
        self.state = state
        self.progress = progress
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.localFilePath = localFilePath
        self.remoteURL = remoteURL
        self.parentId = parentId
        self.groupId = groupId
        self.artworkURL = artworkURL
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

// MARK: - Convenience

extension DownloadItem {

    /// Whether the download has finished successfully and a local file is available.
    public var isAvailableOffline: Bool {
        state == .completed && localFilePath != nil
    }

    /// A formatted string describing the downloaded size (e.g. "12.3 MB / 100.0 MB").
    public var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(downloaded) / \(total)"
    }
}
