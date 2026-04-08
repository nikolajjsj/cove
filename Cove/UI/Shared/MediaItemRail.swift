import Models
import SwiftUI

/// A reusable horizontal scroll rail of media items with skeleton loading.
///
/// Used for "More Like This", "Special Features", "Trailers", etc.
/// Loads data lazily when the section scrolls into view and hides itself
/// entirely when the fetch returns empty or fails.
///
/// This is now a convenience wrapper around ``ContentRail`` with
/// portrait-poster defaults matching the original behavior.
///
/// ```swift
/// MediaItemRail(title: "More Like This") {
///     try await provider.similarItems(for: item, limit: 12)
/// }
/// ```
struct MediaItemRail: View {
    let title: String
    let loader: @Sendable () async throws -> [MediaItem]

    var body: some View {
        ContentRail(
            title: title,
            skeletonCount: 5,
            cardWidth: cardWidth,
            skeleton: { SkeletonCard.poster(width: defaultCardWidth) },
            fetch: loader,
            card: { item in LibraryItemCard(item: item) }
        )
    }

    private var defaultCardWidth: CGFloat { 130 }

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist: 140
        default: 130
        }
    }
}
