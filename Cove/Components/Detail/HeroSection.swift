import ImageService
import SwiftUI

/// A reusable hero section for detail views that displays a full-bleed image
/// with a gradient scrim and an overlay (typically title + subtitle text).
///
/// Consolidates the repeated hero pattern from `MovieDetailView`,
/// `SeriesDetailView`, and `CollectionDetailView`.
///
/// ```swift
/// HeroSection(imageURL: backdropURL, aspectRatio: 4.0 / 5.0) {
///     VStack(alignment: .leading, spacing: 6) {
///         Text(item.title)
///             .font(.system(.title, design: .default, weight: .bold))
///         Text("2024 · 2h 15m")
///             .font(.subheadline)
///             .foregroundStyle(.secondary)
///     }
/// }
/// ```
struct HeroSection<Overlay: View>: View {

    // MARK: - Properties

    /// The primary image URL (typically a backdrop).
    let imageURL: URL?

    /// An optional fallback image URL tried when the primary image fails to load.
    /// Used by collection views that fall back from backdrop → primary artwork.
    var fallbackImageURL: URL?

    /// The aspect ratio of the hero area. Defaults to `4 / 5` (portrait).
    /// Use `16 / 9` for landscape-oriented heroes.
    var aspectRatio: CGFloat = 4.0 / 5.0

    /// Content overlaid at the bottom-leading corner on top of the gradient scrim.
    @ViewBuilder let overlay: () -> Overlay

    // MARK: - Body

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { HeroImageView(imageURL: imageURL, fallbackImageURL: fallbackImageURL) }
            .clipped()
            .overlay(alignment: .bottom) { HeroGradientScrim() }
            .overlay(alignment: .bottomLeading) {
                overlay()
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
    }
}

// MARK: - Subviews

/// Loads the hero image, falling back through `fallbackImageURL` and then
/// a gradient placeholder when neither URL resolves to an image.
private struct HeroImageView: View {
    let imageURL: URL?
    let fallbackImageURL: URL?

    var body: some View {
        LazyImage(url: imageURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if state.isLoading {
                HeroLoadingPlaceholder()
            } else if let fallbackImageURL {
                // Primary failed — try the fallback URL (e.g. primary poster).
                LazyImage(url: fallbackImageURL) { primaryState in
                    if let image = primaryState.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        MediaHeroFallbackGradient()
                    }
                }
            } else {
                MediaHeroFallbackGradient()
            }
        }
    }
}

/// A black rectangle with a centered activity indicator shown while the hero
/// image is being fetched.
private struct HeroLoadingPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                ProgressView()
                    .tint(.white)
            }
    }
}

/// A bottom-to-top gradient that fades the hero image into the system background,
/// giving overlaid text a consistent readable surface.
private struct HeroGradientScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: Color(.systemBackground).opacity(0.6), location: 0.7),
                .init(color: Color(.systemBackground), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A decorative gradient shown when no image is available for the hero area.
///
/// Shared between ``HeroSection`` and ``CompositeHeroSection``.
struct MediaHeroFallbackGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                .blue.opacity(0.3),
                .purple.opacity(0.2),
                .black.opacity(0.8),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Convenience Initializers

extension HeroSection where Overlay == EmptyView {
    /// Creates a hero section with no text overlay — just the image and gradient scrim.
    init(
        imageURL: URL?,
        fallbackImageURL: URL? = nil,
        aspectRatio: CGFloat = 4.0 / 5.0
    ) {
        self.imageURL = imageURL
        self.fallbackImageURL = fallbackImageURL
        self.aspectRatio = aspectRatio
        self.overlay = { EmptyView() }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Hero Section — Portrait") {
        ScrollView {
            HeroSection(imageURL: nil, aspectRatio: 4.0 / 5.0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Movie Title")
                        .font(.system(.title, design: .default, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("2024 · 2h 15m · PG-13")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    #Preview("Hero Section — Landscape") {
        ScrollView {
            HeroSection(imageURL: nil, aspectRatio: 16.0 / 9.0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Collection Name")
                        .font(.system(.title, design: .default, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
#endif
