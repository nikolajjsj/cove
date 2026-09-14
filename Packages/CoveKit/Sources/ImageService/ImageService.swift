import Foundation
import Models
import Nuke
// Re-export NukeUI so consumers only need to import ImageService
@_exported import NukeUI

/// The one image pipeline, and the one artwork store behind it.
///
/// Design, in three decisions:
///
/// 1. **Cache keys are host-independent.** A request is keyed by the URL's path
///    and query — item id, image type, size, tag — never its host. Switching
///    between a LAN and a remote address keeps every cached image, and so does
///    the offline case where the saved URL cannot be reached at all.
/// 2. **One store for on-demand and prefetched artwork.** Views ask for images
///    at the canonical `ArtworkSize`s; the prefetcher fetches exactly those
///    requests. What it stores is what the views hit.
/// 3. **The store lives in Application Support**, excluded from backup, not in
///    Caches: for an offline-first app the artwork is part of working offline,
///    and the user controls its size from Settings. The size limit is 500 MB
///    LRU until "keep all artwork" is on, then effectively unbounded.
public enum ImageService {
    /// Where the artwork lives on disk.
    public static let storeDirectory: URL = {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: AppConstants.bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Artwork", directoryHint: .isDirectory)
    }()

    static let defaultSizeLimit = 500 * 1024 * 1024
    static let keepAllSizeLimit = 20 * 1024 * 1024 * 1024

    private static let dataCache: DataCache? = {
        removeLegacyStore()
        guard let cache = try? DataCache(path: storeDirectory) else { return nil }
        cache.sizeLimit = defaultSizeLimit
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = storeDirectory
        try? dir.setResourceValues(values)
        return cache
    }()

    /// The shared image pipeline configured with disk + memory cache.
    public static let pipeline: ImagePipeline = {
        var config = ImagePipeline.Configuration()
        config.dataCache = dataCache
        // Store what came over the wire, decode on read: the prefetcher writes
        // the same bytes the views later decode, and nothing is stored twice.
        config.dataCachePolicy = .storeOriginalData
        config.imageCache = ImageCache.shared
        ImageCache.shared.costLimit = 200 * 1024 * 1024  // 200 MB memory cache
        ImageCache.shared.countLimit = 500
        config.isProgressiveDecodingEnabled = true
        return ImagePipeline(configuration: config)
    }()

    /// Call once at app startup to set the shared pipeline.
    public static func configure(keepsAllArtwork: Bool) {
        ImagePipeline.shared = pipeline
        setKeepsAllArtwork(keepsAllArtwork)
    }

    /// "Keep all artwork on device": lifts the LRU limit so the prefetched set
    /// is never trimmed. Off, the store returns to a 500 MB LRU cache.
    public static func setKeepsAllArtwork(_ on: Bool) {
        dataCache?.sizeLimit = on ? keepAllSizeLimit : defaultSizeLimit
        if !on { dataCache?.sweep() }
    }

    /// Bytes the store holds right now. Scans the directory; call off the hot path.
    public static var diskUsageBytes: Int {
        dataCache?.totalSize ?? 0
    }

    /// Removes all cached images from both disk and memory.
    public static func clearCache() {
        pipeline.cache.removeAll()
    }

    // MARK: - Requests

    /// The request every view and the prefetcher build for a URL. Same URL,
    /// same request, same cache entry.
    public static func request(for url: URL, priority: ImageRequest.Priority = .normal) -> ImageRequest {
        ImageRequest(url: url, priority: priority, userInfo: [.imageIdKey: cacheKey(for: url)])
    }

    /// Path and query only — `/Items/{id}/Images/Primary?maxWidth=300&…&tag=…`.
    /// Item ids are server GUIDs, so two servers cannot collide; the tag changes
    /// when the server's image does, which is the only invalidation needed.
    public static func cacheKey(for url: URL) -> String {
        var key = url.path(percentEncoded: true)
        if let query = url.query(percentEncoded: true) { key += "?" + query }
        return key
    }

    /// Whether the store already holds the bytes for a URL.
    public static func isCached(_ url: URL) -> Bool {
        pipeline.cache.containsData(for: request(for: url))
    }

    /// Make sure the store holds a URL's bytes, downloading at the lowest
    /// priority if it does not. Returns whether it is there afterwards.
    public static func prefetch(_ url: URL) async -> Bool {
        let request = request(for: url, priority: .veryLow)
        if pipeline.cache.containsData(for: request) { return true }
        do {
            _ = try await pipeline.data(for: request)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Migration

    /// The store used to be Nuke's default location in Caches, keyed by full
    /// URL. Those keys no longer match anything, so the old files are dead
    /// weight: delete them once.
    private static func removeLegacyStore() {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let legacy = caches.appending(path: "\(AppConstants.bundleIdentifier).images", directoryHint: .isDirectory)
        if fm.fileExists(atPath: legacy.path(percentEncoded: false)) {
            try? fm.removeItem(at: legacy)
        }
    }
}
