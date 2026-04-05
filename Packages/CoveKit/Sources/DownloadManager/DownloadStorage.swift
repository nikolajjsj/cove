import Foundation
import Models
import os

/// Manages the on-disk file structure for downloaded media.
///
/// Files are stored under `Library/Application Support/Downloads/` using the hierarchy:
///
///     Downloads/{serverId}/{mediaType}/{itemId}/media.{ext}
///
/// The entire `Downloads` directory is excluded from iCloud backup.
public struct DownloadStorage: Sendable {

    // MARK: - Shared Instance

    public static let shared = DownloadStorage()

    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "DownloadStorage")

    // MARK: - Base Directory

    /// Base downloads directory: `Library/Application Support/Downloads/`
    public var downloadsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Path Helpers

    /// Per-server, per-type directory: `Downloads/{serverId}/{mediaType}/{itemId}/`
    public func itemDirectory(serverId: String, mediaType: MediaType, itemId: ItemID) -> URL {
        downloadsDirectory
            .appendingPathComponent(serverId, isDirectory: true)
            .appendingPathComponent(mediaType.rawValue, isDirectory: true)
            .appendingPathComponent(itemId.rawValue, isDirectory: true)
    }

    /// Server-level directory: `Downloads/{serverId}/`
    public func serverDirectory(serverId: String) -> URL {
        downloadsDirectory.appendingPathComponent(serverId, isDirectory: true)
    }

    /// Derives a file extension from a remote URL string, falling back to a sensible default
    /// based on the media type.
    public func fileExtension(for remoteURL: String, mediaType: MediaType) -> String {
        if let url = URL(string: remoteURL) {
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty && ext.count <= 10 {
                return ext
            }
        }
        // Sensible defaults per media type
        switch mediaType {
        case .movie, .episode:
            return "mp4"
        case .track:
            return "m4a"
        case .book:
            return "epub"
        case .podcast:
            return "mp3"
        case .series, .season, .album, .artist, .playlist:
            return "mp4"
        }
    }

    /// Returns the full file URL where the media file should be stored for a given download item.
    public func mediaFileURL(for item: DownloadItem) -> URL {
        let dir = itemDirectory(
            serverId: item.serverId, mediaType: item.mediaType, itemId: item.itemId)
        let ext = fileExtension(for: item.remoteURL, mediaType: item.mediaType)
        return dir.appendingPathComponent("media.\(ext)")
    }

    /// Returns the relative path (from `downloadsDirectory`) for a given download item's media file.
    ///
    /// This is the value persisted in `DownloadItem.localFilePath`.
    public func relativeFilePath(for item: DownloadItem) -> String {
        let ext = fileExtension(for: item.remoteURL, mediaType: item.mediaType)
        return "\(item.serverId)/\(item.mediaType.rawValue)/\(item.itemId.rawValue)/media.\(ext)"
    }

    /// Resolves a relative local file path back to an absolute URL.
    public func resolveAbsoluteURL(relativePath: String) -> URL {
        downloadsDirectory.appendingPathComponent(relativePath)
    }

    // MARK: - Directory Operations

    /// Create the item directory and set the backup-exclusion flag on the top-level Downloads folder.
    ///
    /// - Parameter item: The download item to prepare storage for.
    /// - Returns: The URL of the directory that was created.
    @discardableResult
    public func prepareDirectory(for item: DownloadItem) throws -> URL {
        let dir = itemDirectory(
            serverId: item.serverId, mediaType: item.mediaType, itemId: item.itemId)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Exclude the top-level Downloads directory from iCloud backup
        var topDir = downloadsDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try topDir.setResourceValues(resourceValues)

        logger.debug("Prepared directory: \(dir.path)")
        return dir
    }

    /// Move a temporary downloaded file to its permanent location.
    ///
    /// - Parameters:
    ///   - temporaryURL: The temporary file location provided by `URLSession`.
    ///   - item: The download item that owns this file.
    /// - Returns: The relative file path suitable for storing in `DownloadItem.localFilePath`.
    @discardableResult
    public func moveToPermamentStorage(from temporaryURL: URL, for item: DownloadItem) throws
        -> String
    {
        let destination = mediaFileURL(for: item)
        let fm = FileManager.default

        // Ensure the parent directory exists
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Remove any existing file at the destination
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        try fm.moveItem(at: temporaryURL, to: destination)

        // Also exclude the item directory from backup for good measure
        var itemDir = destination.deletingLastPathComponent()
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try itemDir.setResourceValues(resourceValues)

        let relativePath = relativeFilePath(for: item)
        logger.info("Moved download to permanent storage: \(relativePath)")
        return relativePath
    }

    // MARK: - Deletion

    /// Delete all downloaded files for a specific item.
    public func deleteFiles(for item: DownloadItem) throws {
        let dir = itemDirectory(
            serverId: item.serverId, mediaType: item.mediaType, itemId: item.itemId)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            logger.info("Deleted files for item \(item.id) at \(dir.path)")
        }

        // Clean up empty parent directories
        cleanupEmptyAncestors(of: dir, upTo: downloadsDirectory)
    }

    /// Delete all downloaded files for a server.
    public func deleteAllFiles(serverId: String) throws {
        let dir = serverDirectory(serverId: serverId)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            logger.info("Deleted all files for server \(serverId)")
        }
    }

    // MARK: - Disk Usage

    /// Calculate total disk usage for a specific server's downloads.
    public func diskUsage(serverId: String) throws -> Int64 {
        let dir = serverDirectory(serverId: serverId)
        return try directorySize(at: dir)
    }

    /// Calculate total disk usage across all downloads.
    public func totalDiskUsage() throws -> Int64 {
        return try directorySize(at: downloadsDirectory)
    }

    /// Check available disk space on the volume containing the downloads directory.
    public func availableDiskSpace() throws -> Int64 {
        let fm = FileManager.default
        // Ensure the directory exists so we can query the volume
        try fm.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let values = try downloadsDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        if let available = values.volumeAvailableCapacityForImportantUsage {
            return available
        }

        // Fallback to the standard available capacity key
        let fallbackValues = try downloadsDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityKey
        ])
        if let available = fallbackValues.volumeAvailableCapacity {
            return Int64(available)
        }

        return 0
    }

    // MARK: - Private Helpers

    /// Recursively calculate the total size of all files within a directory.
    private func directorySize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        var totalSize: Int64 = 0
        guard
            let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .fileSizeKey, .isDirectoryKey,
            ])
            if resourceValues.isDirectory == false {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }

        return totalSize
    }

    /// Remove empty parent directories walking up from `child` towards (but not including) `stop`.
    private func cleanupEmptyAncestors(of child: URL, upTo stop: URL) {
        let fm = FileManager.default
        var current = child.deletingLastPathComponent()

        while current.path != stop.path && current.path.hasPrefix(stop.path) {
            do {
                let contents = try fm.contentsOfDirectory(atPath: current.path)
                if contents.isEmpty {
                    try fm.removeItem(at: current)
                    logger.debug("Cleaned up empty directory: \(current.path)")
                    current = current.deletingLastPathComponent()
                } else {
                    break
                }
            } catch {
                break
            }
        }
    }
}
