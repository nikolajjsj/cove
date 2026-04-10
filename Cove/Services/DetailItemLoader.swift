import Foundation
import Models
import Observation

/// A small `@Observable` loader that fetches the full detail version of a
/// `MediaItem` (with people, remote trailers, etc.) and exposes it for views
/// that show an item passed via navigation but need enriched data.
///
/// Both `MovieDetailView` and `SeriesDetailView` previously duplicated an
/// identical `fetchFullItem()` / `detailedItem` / `displayItem` pattern.
/// This type extracts that into a single reusable piece.
///
/// Usage:
/// ```swift
/// @State private var detailLoader = DetailItemLoader()
///
/// private var displayItem: MediaItem {
///     detailLoader.displayItem(fallback: item)
/// }
///
/// // In .task:
/// await detailLoader.load {
///     try await appState.provider.item(id: item.id)
/// }
/// ```
@MainActor
@Observable
final class DetailItemLoader {

    /// The fully-fetched item, or `nil` if the fetch hasn't completed (or failed).
    private(set) var item: MediaItem?

    /// Returns the enriched item when available, otherwise falls back to the
    /// navigation-provided item so the view always has something to display.
    func displayItem(fallback: MediaItem) -> MediaItem {
        item ?? fallback
    }

    /// Fetches the detailed item using the provided closure.
    ///
    /// On failure the loader silently stays `nil` — the view continues to use
    /// the fallback item and supplementary sections (people, trailers) simply
    /// won't appear.
    ///
    /// - Parameter fetch: An async throwing closure that returns the full item.
    func load(_ fetch: @Sendable () async throws -> MediaItem) async {
        do {
            let full = try await fetch()
            guard !Task.isCancelled else { return }
            item = full
        } catch {
            // Silently fall back — people / remote trailers just won't show.
        }
    }
}
