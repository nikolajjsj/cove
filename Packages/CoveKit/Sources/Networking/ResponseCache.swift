import Foundation

/// A lightweight, thread-safe, in-memory cache for API responses with
/// TTL (time-to-live) based expiry.
///
/// `ResponseCache` is designed to sit between the HTTP client and the
/// network, eliminating redundant requests for data that changes
/// infrequently (library listings, item metadata, etc.).
///
/// ## Design Decisions
///
/// - **Actor-based**: Guarantees data-race safety under Swift 6 strict
///   concurrency without manual locking.
/// - **TTL per-entry**: Each entry records its insertion time; staleness
///   is evaluated at read time against a caller-supplied `maxAge`.
/// - **LRU-ish eviction**: When the cache exceeds `maxEntries`, the
///   oldest quarter of entries (by insertion time) is evicted in bulk.
///   This avoids per-access bookkeeping while keeping memory bounded.
/// - **Key design**: Callers are expected to use the full request URL
///   (including query string) as the cache key, so identical requests
///   always hit the same entry.
public actor ResponseCache {

    // MARK: - Types

    private struct Entry {
        let data: Data
        let timestamp: Date
    }

    // MARK: - Storage

    private var entries: [String: Entry] = [:]
    private let maxEntries: Int

    // MARK: - Init

    /// Creates a new response cache.
    ///
    /// - Parameter maxEntries: Upper bound on the number of cached
    ///   responses. When exceeded, the oldest 25 % of entries are
    ///   evicted. Defaults to 200.
    public init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    // MARK: - Read

    /// Returns the cached data for `key` if it exists **and** was stored
    /// less than `maxAge` seconds ago. Expired entries are removed eagerly.
    ///
    /// - Parameters:
    ///   - key: The cache key (typically the full request URL string).
    ///   - maxAge: Maximum acceptable age in seconds.
    /// - Returns: The cached `Data`, or `nil` on a miss / expiry.
    public func get(forKey key: String, maxAge: TimeInterval) -> Data? {
        guard let entry = entries[key] else { return nil }

        if Date().timeIntervalSince(entry.timestamp) < maxAge {
            return entry.data
        }

        // Entry is stale — remove it.
        entries.removeValue(forKey: key)
        return nil
    }

    // MARK: - Write

    /// Stores `data` in the cache under `key`, evicting old entries if
    /// the cache is at capacity.
    ///
    /// - Parameters:
    ///   - data: The response data to cache.
    ///   - key: The cache key.
    public func set(_ data: Data, forKey key: String) {
        evictIfNeeded()
        entries[key] = Entry(data: data, timestamp: Date())
    }

    // MARK: - Removal

    /// Removes the entry for `key`, if present.
    public func remove(forKey key: String) {
        entries.removeValue(forKey: key)
    }

    /// Removes all entries whose key contains the given substring.
    ///
    /// This is useful for targeted invalidation — for example, removing
    /// all cached responses that reference a specific item ID after the
    /// user modifies that item.
    public func removeAll(matching substring: String) {
        for key in entries.keys where key.contains(substring) {
            entries.removeValue(forKey: key)
        }
    }

    /// Removes every entry from the cache.
    public func removeAll() {
        entries.removeAll()
    }

    // MARK: - Diagnostics

    /// The current number of entries in the cache.
    public var count: Int {
        entries.count
    }

    // MARK: - Private

    /// Evicts the oldest 25 % of entries when the cache exceeds its
    /// capacity limit.
    private func evictIfNeeded() {
        guard entries.count >= maxEntries else { return }

        let evictionCount = max(entries.count / 4, 1)
        let keysToEvict =
            entries
            .sorted { $0.value.timestamp < $1.value.timestamp }
            .prefix(evictionCount)
            .map(\.key)

        for key in keysToEvict {
            entries.removeValue(forKey: key)
        }
    }
}

// MARK: - Cache Policy

/// Controls whether and how an HTTP response may be served from the
/// in-memory `ResponseCache`.
///
/// Attach a policy to individual `HTTPClient` requests to opt in to
/// caching on a per-endpoint basis.
public enum CachePolicy: Sendable {
    /// Always fetch from the network. The response is **not** stored in
    /// the in-memory cache. This is the default and should be used for
    /// mutating operations and user-specific volatile data.
    case networkOnly

    /// Return a cached response if one exists and is younger than
    /// `maxAge` seconds. Otherwise, fetch from the network and cache
    /// the result for future callers.
    ///
    /// Good defaults:
    /// - Library / folder listings: **300 s** (5 min)
    /// - Item lists (browse, search): **120 s** (2 min)
    /// - Single-item detail: **120 s** (2 min)
    /// - Resume / "continue watching": **30 s**
    case cacheFirst(maxAge: TimeInterval)
}
