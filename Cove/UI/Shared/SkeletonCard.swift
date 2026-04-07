import SwiftUI

/// A universal loading placeholder for media cards.
///
/// Replaces `AlbumCardPlaceholder`, `AlbumShelfPlaceholder`, `SongCardPlaceholder`,
/// and the private `SkeletonItemCard` in `MediaItemRail`. Use the convenience
/// static properties for common configurations.
struct SkeletonCard: View {
    var width: CGFloat? = nil
    var aspectRatio: CGFloat = 1
    var cornerRadius: CGFloat = 8
    var lineCount: Int = 1
    var isCircular: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCircular {
                Circle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: .fill)
            }

            ForEach(0..<lineCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(
                        width: index > 0 ? textLineWidth(index) : nil,
                        height: index == 0 ? 12 : 10
                    )
            }
        }
        .frame(maxWidth: width ?? .infinity)
    }

    /// Progressively shorter lines after the first.
    private func textLineWidth(_ index: Int) -> CGFloat? {
        guard let width else { return 60 }
        return width * (index == 1 ? 0.6 : 0.4)
    }
}

// MARK: - Convenience Presets

extension SkeletonCard {
    /// Placeholder for an album card in a grid.
    static var albumGrid: SkeletonCard {
        SkeletonCard(aspectRatio: 1, lineCount: 1)
    }

    /// Placeholder for an album card in a horizontal shelf.
    static func albumShelf(width: CGFloat = 140) -> SkeletonCard {
        SkeletonCard(width: width, aspectRatio: 1, lineCount: 1)
    }

    /// Placeholder for an artist card (circular artwork).
    static var artist: SkeletonCard {
        SkeletonCard(aspectRatio: 1, isCircular: true)
    }

    /// Placeholder for a song card with subtitle.
    static var song: SkeletonCard {
        SkeletonCard(aspectRatio: 1, lineCount: 2)
    }

    /// Placeholder for a poster-style card (2:3 ratio).
    static func poster(width: CGFloat = 130) -> SkeletonCard {
        SkeletonCard(width: width, aspectRatio: 2.0 / 3.0, lineCount: 2)
    }

    /// Placeholder for a landscape video thumbnail.
    static func landscape(width: CGFloat = 220) -> SkeletonCard {
        SkeletonCard(width: width, aspectRatio: 16.0 / 9.0, lineCount: 2)
    }
}

#Preview("Skeleton Card Variants") {
    ScrollView {
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                SkeletonCard.albumGrid
                    .frame(width: 140)
                SkeletonCard.artist
                    .frame(width: 140)
            }

            HStack(spacing: 16) {
                SkeletonCard.song
                    .frame(width: 140)
                SkeletonCard.poster()
            }

            SkeletonCard.landscape()
        }
        .padding()
    }
}
