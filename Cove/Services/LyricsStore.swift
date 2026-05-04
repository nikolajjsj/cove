import Foundation
import MediaServerKit
import Models

/// A session-scoped, in-memory cache for track lyrics.
///
/// Prevents duplicate network requests when multiple views need lyrics for the
/// same track simultaneously — for example when `CurrentLyricPreview` is already
/// showing on the artwork page while the user switches to `LyricsView`.
///
/// Concurrent requests for the same track are coalesced into a single fetch, so
/// the server is never contacted twice for the same track within a session.
///
/// ## Usage
/// ```swift
/// // In a view that already has AppState and AuthManager in the environment:
/// let lyrics = await appState.lyricsStore.lyrics(for: track.id, using: authManager.provider)
/// ```
@Observable
@MainActor
final class LyricsStore {

    // MARK: - Cache

    private enum Entry {
        /// Lyrics were fetched successfully and are available.
        case available(Lyrics)
        /// The fetch succeeded but the track has no lyrics, or it failed.
        case unavailable
    }

    private var cache: [TrackID: Entry] = [:]

    /// In-flight fetch tasks keyed by track ID.
    ///
    /// Concurrent callers for the same track await the same underlying task,
    /// ensuring exactly one network request is in flight per track at a time.
    @ObservationIgnored
    private var inFlight: [TrackID: Task<Lyrics?, Never>] = [:]

    // MARK: - Public API

    /// Return the lyrics for a track, fetching from the server if not already cached.
    ///
    /// Multiple concurrent calls for the same `trackID` are coalesced — only one
    /// network request is made regardless of how many callers are waiting.
    ///
    /// - Parameters:
    ///   - trackID: The track whose lyrics to retrieve.
    ///   - provider: The `MusicProvider` used for the network fetch.
    /// - Returns: The ``Lyrics`` if available, or `nil` if the track has none or
    ///   the fetch failed.
    func lyrics(for trackID: TrackID, using provider: any MusicProvider) async -> Lyrics? {
        // Positive or negative cache hit — return immediately without a network call.
        switch cache[trackID] {
        case .available(let lyrics): return lyrics
        case .unavailable: return nil
        case nil: break
        }

        // Coalesce onto an already-in-flight request for the same track.
        if let existing = inFlight[trackID] {
            return await existing.value
        }

        // No cache entry and no in-flight request — start a fresh fetch.
        let task = Task<Lyrics?, Never> { @MainActor [weak self] in
            let result = try? await provider.lyrics(track: trackID)
            self?.cache[trackID] = result.map { .available($0) } ?? .unavailable
            self?.inFlight.removeValue(forKey: trackID)
            return result
        }
        inFlight[trackID] = task
        return await task.value
    }

    /// Discard cached lyrics for a track, forcing a fresh fetch on the next access.
    ///
    /// Useful if the server-side lyrics for the track may have changed.
    func invalidate(_ trackID: TrackID) {
        cache.removeValue(forKey: trackID)
        inFlight[trackID]?.cancel()
        inFlight.removeValue(forKey: trackID)
    }

    /// Clear the entire cache and cancel all in-flight requests.
    ///
    /// Typically called on server disconnect.
    func invalidateAll() {
        cache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}
