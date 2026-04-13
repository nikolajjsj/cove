import Models
import SwiftUI

/// A reusable horizontal scroll rail of media items with skeleton loading.
///
/// Used for "More Like This", "Special Features", "Trailers", etc.
/// Loads data lazily when the section scrolls into view and hides itself
/// entirely when the fetch returns empty or fails.
///
/// Pass `style: .landscape` for video-clip rails (trailers, special features)
/// to get 16:9 thumbnails with a tappable play button instead of portrait posters.
///
/// ```swift
/// // Portrait rail (default) — "More Like This", recommendations
/// MediaItemRail(title: "More Like This") {
///     try await provider.similarItems(for: item, limit: 12)
/// }
///
/// // Landscape rail — trailers and special features
/// MediaItemRail(title: "Trailers", style: .landscape) {
///     try await provider.localTrailers(for: item)
/// }
/// ```
struct MediaItemRail: View {
    let title: String
    let style: MediaCard.Style
    let loader: @Sendable () async throws -> [MediaItem]

    init(
        title: String,
        style: MediaCard.Style = .portrait,
        loader: @escaping @Sendable () async throws -> [MediaItem]
    ) {
        self.title = title
        self.style = style
        self.loader = loader
    }

    var body: some View {
        ContentRail(
            title: title,
            skeletonCount: style == .landscape ? 4 : 5,
            cardWidth: cardWidth,
            skeleton: {
                style == .landscape
                    ? SkeletonCard.landscape(width: landscapeCardWidth)
                    : SkeletonCard.poster(width: portraitCardWidth)
            },
            fetch: loader,
            card: { item in MediaCard(item: item, style: style) }
        )
    }

    // MARK: - Dimensions

    private let portraitCardWidth: CGFloat = 130
    private let landscapeCardWidth: CGFloat = 240

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch style {
        case .landscape:
            return landscapeCardWidth
        case .portrait:
            switch item.mediaType {
            case .album, .artist, .track, .playlist:
                return 140
            default:
                return portraitCardWidth
            }
        }
    }
}
