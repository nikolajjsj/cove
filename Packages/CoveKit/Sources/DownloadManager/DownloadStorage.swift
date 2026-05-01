import Foundation
import Models
import UniformTypeIdentifiers
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

    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier, category: "DownloadStorage")

    // MARK: - Base Directory

    /// Base downloads directory: `Library/Application Support/Downloads/`
    public var downloadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    // MARK: - Path Helpers

    /// Per-server, per-type directory: `Downloads/{serverId}/{mediaType}/{itemId}/`
    public func itemDirectory(serverId: String, mediaType: MediaType, itemId: ItemID) -> URL {
        downloadsDirectory
            .appending(path: serverId, directoryHint: .isDirectory)
            .appending(path: mediaType.rawValue, directoryHint: .isDirectory)
            .appending(path: itemId.rawValue, directoryHint: .isDirectory)
    }

    /// Server-level directory: `Downloads/{serverId}/`
    public func serverDirectory(serverId: String) -> URL {
        downloadsDirectory.appending(path: serverId, directoryHint: .isDirectory)
    }

    /// Determines the file extension from an HTTP response.
    ///
    /// Resolution order:
    /// 1. `response.suggestedFilename` (parses `Content-Disposition` for us).
    /// 2. `response.mimeType` mapped to an extension via `UTType`.
    /// 3. Returns `nil` if neither approach yields a valid extension — the
    ///    caller should fail the download with a clear error message.
    public func fileExtension(from response: HTTPURLResponse) -> String? {
        // 1. Try the suggested filename (derived from Content-Disposition)
        if let suggested = response.suggestedFilename {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if !ext.isEmpty && ext.count <= 10 {
                return ext
            }
        }

        // 2. Fall back to UTType MIME → extension mapping
        if let mime = response.mimeType?.lowercased(),
            mime != "application/octet-stream",
            let utType = UTType(mimeType: mime),
            let ext = utType.preferredFilenameExtension
        {
            return ext
        }

        return nil
    }

    /// Returns the full file URL where the media file should be stored for a given download item.
    public func mediaFileURL(for item: DownloadItem, fileExtension ext: String) -> URL {
        let dir = itemDirectory(
            serverId: item.serverId,
            mediaType: item.mediaType,
            itemId: item.itemId
        )
        return dir.appending(path: "media.\(ext)")
    }

    /// Returns the relative path (from `downloadsDirectory`) for a given download item's media file.
    ///
    /// This is the value persisted in `DownloadItem.localFilePath`.
    public func relativeFilePath(for item: DownloadItem, fileExtension ext: String) -> String {
        return "\(item.serverId)/\(item.mediaType.rawValue)/\(item.itemId.rawValue)/media.\(ext)"
    }

    /// Resolves a relative local file path back to an absolute URL.
    public func resolveAbsoluteURL(relativePath: String) -> URL {
        downloadsDirectory.appending(path: relativePath)
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
    public func moveToPermamentStorage(
        from temporaryURL: URL, for item: DownloadItem, fileExtension ext: String
    ) throws
        -> String
    {
        let destination = mediaFileURL(for: item, fileExtension: ext)
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

        let relativePath = relativeFilePath(for: item, fileExtension: ext)
        logger.info("Moved download to permanent storage: \(relativePath)")
        return relativePath
    }

    // MARK: - Artwork & Subtitle Paths

    /// Returns the URL where a primary image should be stored for an item.
    ///
    /// Layout: `Downloads/{serverId}/{mediaType}/{itemId}/primary.jpg`
    public func primaryImageURL(serverId: String, mediaType: MediaType, itemId: ItemID) -> URL {
        itemDirectory(serverId: serverId, mediaType: mediaType, itemId: itemId)
            .appending(path: "primary.jpg")
    }

    /// Returns the URL where a backdrop image should be stored for an item.
    ///
    /// Layout: `Downloads/{serverId}/{mediaType}/{itemId}/backdrop.jpg`
    public func backdropImageURL(serverId: String, mediaType: MediaType, itemId: ItemID) -> URL {
        itemDirectory(serverId: serverId, mediaType: mediaType, itemId: itemId)
            .appending(path: "backdrop.jpg")
    }

    /// Returns the URL where a subtitle file should be stored.
    ///
    /// Layout: `Downloads/{serverId}/{mediaType}/{itemId}/sub_{index}_{language}.{format}`
    public func subtitleURL(
        serverId: String,
        mediaType: MediaType,
        itemId: ItemID,
        index: Int,
        language: String?,
        format: String = "vtt"
    ) -> URL {
        let lang = language ?? "und"
        let filename = "sub_\(index)_\(lang).\(format)"
        return itemDirectory(serverId: serverId, mediaType: mediaType, itemId: itemId)
            .appending(path: filename)
    }

    /// Returns the relative path (from `downloadsDirectory`) for a primary image.
    public func relativePrimaryImagePath(serverId: String, mediaType: MediaType, itemId: ItemID)
        -> String
    {
        "\(serverId)/\(mediaType.rawValue)/\(itemId.rawValue)/primary.jpg"
    }

    /// Returns the relative path (from `downloadsDirectory`) for a backdrop image.
    public func relativeBackdropImagePath(serverId: String, mediaType: MediaType, itemId: ItemID)
        -> String
    {
        "\(serverId)/\(mediaType.rawValue)/\(itemId.rawValue)/backdrop.jpg"
    }

    /// Returns the relative path (from `downloadsDirectory`) for a subtitle file.
    public func relativeSubtitlePath(
        serverId: String,
        mediaType: MediaType,
        itemId: ItemID,
        index: Int,
        language: String?,
        format: String = "vtt"
    ) -> String {
        let lang = language ?? "und"
        return "\(serverId)/\(mediaType.rawValue)/\(itemId.rawValue)/sub_\(index)_\(lang).\(format)"
    }

    /// Resolve a local image URL for offline display.
    /// Returns `nil` if the file does not exist on disk.
    public func localImageURL(relativePath: String) -> URL? {
        let url = resolveAbsoluteURL(relativePath: relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Download a remote image to a local file path.
    /// This is a simple synchronous file write — intended to be called from a background task.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL to download from.
    ///   - destinationURL: The local file URL to write to.
    /// - Returns: `true` if the download succeeded, `false` otherwise.
    @discardableResult
    public func downloadImage(from remoteURL: URL, to destinationURL: URL) async -> Bool {
        do {
            let fm = FileManager.default
            try fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let (data, response) = try await URLSession.shared.data(from: remoteURL)

            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode),
                !data.isEmpty
            else {
                logger.warning(
                    "Failed to download image from \(remoteURL.absoluteString): bad response")
                return false
            }

            // Remove existing file if present
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL)
            logger.debug("Downloaded image to \(destinationURL.lastPathComponent)")
            return true
        } catch {
            logger.warning(
                "Failed to download image from \(remoteURL.absoluteString): \(error.localizedDescription)"
            )
            return false
        }
    }

    /// Prepare directory for a parent item (series, album) that has no media file but needs artwork.
    ///
    /// - Parameters:
    ///   - serverId: The server connection ID.
    ///   - mediaType: The media type of the parent.
    ///   - itemId: The parent item ID.
    @discardableResult
    public func prepareParentDirectory(serverId: String, mediaType: MediaType, itemId: ItemID)
        throws -> URL
    {
        let dir = itemDirectory(serverId: serverId, mediaType: mediaType, itemId: itemId)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Exclude from backup
        var topDir = downloadsDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try topDir.setResourceValues(resourceValues)

        return dir
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

    // MARK: - Orphan Cleanup

    /// Remove any leftover files in the `.staging` directory.
    ///
    /// The staging directory is used as a temporary holding area when downloads
    /// complete. If the app crashes between staging and the final move to
    /// permanent storage, staged files remain as orphans. Call this on launch
    /// to reclaim the space.
    public func cleanupStagingDirectory() {
        let stagingDir = downloadsDirectory.appending(path: ".staging", directoryHint: .isDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: stagingDir.path) else { return }
        do {
            try fm.removeItem(at: stagingDir)
            logger.info("Cleaned up staging directory")
        } catch {
            logger.warning("Failed to clean staging directory: \(error.localizedDescription)")
        }
    }

    /// Delete a specific item's directory using raw identifiers.
    ///
    /// This is used to clean up artwork directories for parent items (series,
    /// albums, seasons, playlists) that no longer have any child downloads.
    ///
    /// - Parameters:
    ///   - serverId: The server connection UUID string.
    ///   - mediaType: The raw media type string (e.g. "series", "album").
    ///   - itemId: The item's raw identifier string.
    public func deleteItemDirectoryByRawId(
        serverId: String, mediaType: String, itemId: String
    ) throws {
        let dir =
            downloadsDirectory
            .appending(path: serverId, directoryHint: .isDirectory)
            .appending(path: mediaType, directoryHint: .isDirectory)
            .appending(path: itemId, directoryHint: .isDirectory)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            logger.info("Deleted item directory: \(dir.path)")
        }
        cleanupEmptyAncestors(of: dir, upTo: downloadsDirectory)
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
