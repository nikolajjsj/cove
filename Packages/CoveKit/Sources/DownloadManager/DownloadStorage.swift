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

    /// Where the `Downloads` tree is rooted. `nil` means Application Support.
    ///
    /// Tests point this at a temporary directory so they can exercise the real
    /// staging, move, and delete logic without touching the app's own storage.
    private let rootDirectory: URL?

    /// Creates a storage helper rooted at Application Support.
    public init() { self.rootDirectory = nil }

    /// Creates a storage helper rooted at an arbitrary directory, for tests.
    public init(rootDirectory: URL) { self.rootDirectory = rootDirectory }

    /// Base downloads directory: `<root>/Downloads/`
    public var downloadsDirectory: URL {
        (rootDirectory ?? URL.applicationSupportDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
    }

    // MARK: - Path Safety

    /// Reduce an untrusted identifier to a single safe path component.
    ///
    /// `URL.appending(path:)` is a *path* append, not a component append: it
    /// neither escapes `/` nor collapses `..`, and `FileManager` resolves both at
    /// syscall time. Item ids, media-type strings and subtitle language tags all
    /// arrive from the media server, so letting any of them reach a URL unfiltered
    /// is a directory-traversal primitive — `deleteFiles` would `removeItem` a
    /// directory of the server's choosing, and `downloadImage` would write bytes
    /// there.
    ///
    /// Jellyfin item ids are hex GUIDs and pass through unchanged. The mapping is
    /// deterministic, so a given id always resolves to the same directory and
    /// lookups stay consistent across launches.
    static func safeComponent(_ raw: String) -> String {
        let mapped = String(
            raw.map { character in
                if character.isASCII, character.isLetter || character.isNumber { return character }
                if character == "-" || character == "_" { return character }
                return "_"
            })
        return mapped.isEmpty ? "_" : String(mapped.prefix(128))
    }

    /// Verify a URL really lands inside the downloads tree.
    ///
    /// ``safeComponent(_:)`` is the primary defence; this is the backstop for
    /// paths that arrive already assembled — notably `DownloadItem.localFilePath`,
    /// which is persisted and so may have been written by a build that predates
    /// the sanitiser.
    func isContained(_ url: URL) -> Bool {
        let base = downloadsDirectory.standardizedFileURL.path
        let resolved = url.standardizedFileURL.path
        // The trailing separator matters: without it a sibling `Downloads-evil`
        // would also satisfy the prefix test.
        return resolved == base || resolved.hasPrefix(base + "/")
    }

    // MARK: - Path Helpers

    /// Per-server, per-type directory: `Downloads/{serverId}/{mediaType}/{itemId}/`
    public func itemDirectory(serverId: String, mediaType: MediaType, itemId: ItemID) -> URL {
        downloadsDirectory
            .appending(path: Self.safeComponent(serverId), directoryHint: .isDirectory)
            .appending(path: Self.safeComponent(mediaType.rawValue), directoryHint: .isDirectory)
            .appending(path: Self.safeComponent(itemId.rawValue), directoryHint: .isDirectory)
    }

    /// Server-level directory: `Downloads/{serverId}/`
    public func serverDirectory(serverId: String) -> URL {
        downloadsDirectory.appending(
            path: Self.safeComponent(serverId), directoryHint: .isDirectory)
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
        return dir.appending(path: "media.\(Self.safeComponent(ext))")
    }

    /// Returns the relative path (from `downloadsDirectory`) for a given download item's media file.
    ///
    /// This is the value persisted in `DownloadItem.localFilePath`.
    public func relativeFilePath(for item: DownloadItem, fileExtension ext: String) -> String {
        return "\(Self.safeComponent(item.serverId))/\(Self.safeComponent(item.mediaType.rawValue))/\(Self.safeComponent(item.itemId.rawValue))/media.\(Self.safeComponent(ext))"
    }

    /// Resolves a relative local file path back to an absolute URL.
    ///
    /// Returns a path inside the downloads tree or nothing: `localFilePath` is
    /// persisted, so a row written before ``safeComponent(_:)`` existed may still
    /// carry a traversal.
    public func resolveAbsoluteURL(relativePath: String) -> URL {
        let url = downloadsDirectory.appending(path: relativePath)
        guard isContained(url) else {
            logger.error("Refusing to resolve a path outside Downloads: \(relativePath)")
            // A path that cannot be resolved safely must not fall back to the
            // downloads root — callers read and delete through this.
            return downloadsDirectory.appending(path: Self.safeComponent(relativePath))
        }
        return url
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
        "\(Self.safeComponent(serverId))/\(Self.safeComponent(mediaType.rawValue))/\(Self.safeComponent(itemId.rawValue))/primary.jpg"
    }

    /// Returns the relative path (from `downloadsDirectory`) for a backdrop image.
    public func relativeBackdropImagePath(serverId: String, mediaType: MediaType, itemId: ItemID)
        -> String
    {
        "\(Self.safeComponent(serverId))/\(Self.safeComponent(mediaType.rawValue))/\(Self.safeComponent(itemId.rawValue))/backdrop.jpg"
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
        return "\(Self.safeComponent(serverId))/\(Self.safeComponent(mediaType.rawValue))/\(Self.safeComponent(itemId.rawValue))/sub_\(index)_\(Self.safeComponent(lang)).\(Self.safeComponent(format))"
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
        // removeItem is recursive; never let it run outside the downloads tree.
        guard isContained(dir) else {
            logger.error("Refusing to delete outside Downloads: \(dir.path)")
            return
        }
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
    ///
    /// This is the authoritative figure for "space used by downloads": it counts
    /// media files, artwork, subtitles, and any orphaned staging files.
    public func totalDiskUsage() throws -> Int64 {
        return try directorySize(at: downloadsDirectory)
    }

    /// Calculate disk usage for a single item's directory.
    ///
    /// This includes everything stored alongside the media file — artwork and
    /// subtitle sidecars — so per-item sizes add up to the server total.
    public func diskUsage(serverId: String, mediaType: MediaType, itemId: ItemID) throws -> Int64 {
        let dir = itemDirectory(serverId: serverId, mediaType: mediaType, itemId: itemId)
        return try directorySize(at: dir)
    }

    /// Calculate disk usage for a single download item.
    public func diskUsage(for item: DownloadItem) throws -> Int64 {
        try diskUsage(serverId: item.serverId, mediaType: item.mediaType, itemId: item.itemId)
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
            .appending(path: Self.safeComponent(serverId), directoryHint: .isDirectory)
            .appending(path: Self.safeComponent(mediaType), directoryHint: .isDirectory)
            .appending(path: Self.safeComponent(itemId), directoryHint: .isDirectory)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            logger.info("Deleted item directory: \(dir.path)")
        }
        cleanupEmptyAncestors(of: dir, upTo: downloadsDirectory)
    }

    // MARK: - Private Helpers

    /// Recursively calculate the total size of all files within a directory.
    ///
    /// Hidden entries are deliberately included so that orphaned files in
    /// `.staging` are reported as the space they actually occupy.
    private func directorySize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        var totalSize: Int64 = 0
        guard
            let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: []
            )
        else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            // A single unreadable entry must not discard the whole measurement,
            // which would make the UI report 0 bytes used.
            guard
                let resourceValues = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey,
                ]),
                resourceValues.isRegularFile == true
            else {
                continue
            }
            totalSize += Int64(resourceValues.fileSize ?? 0)
        }

        return totalSize
    }

    /// Remove empty parent directories walking up from `child` towards (but not
    /// including) `stop`.
    ///
    /// Both ends are standardised first. Comparing raw paths let a `..` survive
    /// into the prefix test, which a traversed path satisfies while actually
    /// resolving outside `stop` — and `deletingLastPathComponent()` on a path
    /// ending in `..` returns the same string, so the loop could neither advance
    /// nor terminate.
    private func cleanupEmptyAncestors(of child: URL, upTo stop: URL) {
        let fm = FileManager.default
        let stop = stop.standardizedFileURL
        var current = child.standardizedFileURL.deletingLastPathComponent()

        while current.path != stop.path && current.path.hasPrefix(stop.path + "/") {
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
