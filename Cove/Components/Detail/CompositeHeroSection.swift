import ImageService
import Models
import SwiftUI

/// A cinematic hero section that layers a floating poster card over a landscape
/// backdrop image, with title and subtitle information alongside the poster.
///
/// Used by `VideoDetailScaffold` when a poster URL is provided, giving movie
/// and series detail views a richer visual identity reminiscent of streaming apps.
///
/// The poster overlaps the bottom edge of the backdrop, creating a layered
/// depth effect. The title, original title, subtitle parts, and tagline are
/// displayed to the right of the poster.
///
/// ```swift
/// CompositeHeroSection(
///     backdropURL: backdropURL,
///     posterURL: posterURL,
///     title: item.title,
///     originalTitle: displayItem.originalTitle,
///     subtitleParts: heroSubtitleParts,
///     tagline: displayItem.tagline
/// )
/// ```
struct CompositeHeroSection: View {

    // MARK: - Properties

    /// The backdrop image URL (landscape, typically 16:9).
    let backdropURL: URL?

    /// The poster artwork URL (portrait, typically 2:3).
    let posterURL: URL?

    /// The primary title of the media item.
    let title: String

    /// The original title (shown when different from `title`).
    var originalTitle: String? = nil

    /// Dot-separated subtitle parts (e.g. "2024", "R", "2h 15m").
    var subtitleParts: [String] = []

    /// An optional tagline displayed in italic below the subtitle.
    var tagline: String? = nil

    /// Whether the item is marked as a favorite.
    var isFavorite: Bool = false

    /// Whether the item has been fully watched.
    var isPlayed: Bool = false

    // MARK: - Constants

    /// Width of the floating poster card.
    private let posterWidth: CGFloat = 110

    /// How far the poster + title section overlaps into the backdrop.
    private let overlapHeight: CGFloat = 72

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Landscape backdrop with gradient scrim
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { CompositeBackdropImageView(backdropURL: backdropURL) }
                .clipped()
                .overlay(alignment: .bottom) { CompositeGradientScrim() }

            // Poster + title row, pulled up to overlap the backdrop
            CompositePosterTitleRow(
                posterURL: posterURL,
                isPlayed: isPlayed,
                posterWidth: posterWidth,
                title: title,
                originalTitle: originalTitle,
                subtitleParts: subtitleParts,
                tagline: tagline,
                isFavorite: isFavorite
            )
            .padding(.top, -overlapHeight)
        }
        // Add bottom space so content below isn't clipped by the overlap
        .padding(.bottom, 4)
    }
}

// MARK: - Backdrop

/// Loads the backdrop image with a loading placeholder and ``MediaHeroFallbackGradient``
/// when no image is available.
private struct CompositeBackdropImageView: View {
    let backdropURL: URL?

    var body: some View {
        LazyImage(url: backdropURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if state.isLoading {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            } else {
                MediaHeroFallbackGradient()
            }
        }
    }
}

/// A bottom-to-top gradient that fades the backdrop into the system background.
private struct CompositeGradientScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.2),
                .init(color: Color(.systemBackground).opacity(0.5), location: 0.6),
                .init(color: Color(.systemBackground).opacity(0.85), location: 0.85),
                .init(color: Color(.systemBackground), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Poster + Title Row

/// The horizontal stack that positions the floating poster card alongside the
/// title / metadata column, offset upwards to overlap the backdrop.
private struct CompositePosterTitleRow: View {
    let posterURL: URL?
    let isPlayed: Bool
    let posterWidth: CGFloat
    let title: String
    let originalTitle: String?
    let subtitleParts: [String]
    let tagline: String?
    let isFavorite: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            CompositePosterCard(posterURL: posterURL, isPlayed: isPlayed, posterWidth: posterWidth)

            CompositeTitleColumn(
                title: title,
                originalTitle: originalTitle,
                subtitleParts: subtitleParts,
                tagline: tagline,
                isFavorite: isFavorite
            )
            .padding(.bottom, 4)
        }
        .padding(.horizontal)
    }
}

// MARK: - Poster Card

/// The floating poster artwork with an optional ``WatchedBadge``.
private struct CompositePosterCard: View {
    let posterURL: URL?
    let isPlayed: Bool
    let posterWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MediaImage.poster(
                url: posterURL,
                aspectRatio: 2.0 / 3.0,
                icon: "film",
                cornerRadius: 12
            )

            if isPlayed {
                WatchedBadge()
            }
        }
        .frame(width: posterWidth)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

// MARK: - Title Column

/// The vertical stack of title, original title, subtitle parts, and tagline.
private struct CompositeTitleColumn: View {
    let title: String
    let originalTitle: String?
    let subtitleParts: [String]
    let tagline: String?
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            if let originalTitle,
                !originalTitle.isEmpty,
                originalTitle != title
            {
                Text(originalTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1)
            }

            if !subtitleParts.isEmpty {
                DotSeparatedText(
                    parts: subtitleParts,
                    font: .caption,
                    foregroundStyle: .secondary
                )
            }

            if let tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Composite Hero — Movie") {
        ScrollView {
            CompositeHeroSection(
                backdropURL: nil,
                posterURL: nil,
                title: "The Shawshank Redemption",
                originalTitle: "Die Verurteilten",
                subtitleParts: ["1994", "R", "2h 22m"],
                tagline: "Fear can hold you prisoner. Hope can set you free.",
                isPlayed: true
            )
        }
        .ignoresSafeArea(edges: .top)
    }

    #Preview("Composite Hero — Series") {
        ScrollView {
            CompositeHeroSection(
                backdropURL: nil,
                posterURL: nil,
                title: "Breaking Bad",
                subtitleParts: ["2008 – 2013", "TV-MA", "5 Seasons"],
                isFavorite: true
            )
        }
        .ignoresSafeArea(edges: .top)
    }

    #Preview("Composite Hero — Long Title") {
        ScrollView {
            CompositeHeroSection(
                backdropURL: nil,
                posterURL: nil,
                title: "Everything Everywhere All at Once",
                subtitleParts: ["Mar 25, 2022", "R", "2h 19m"],
                tagline: "The universe is so much bigger than you realize."
            )
        }
        .ignoresSafeArea(edges: .top)
    }
#endif
