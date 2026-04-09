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
            .overlay { heroImage }
            .clipped()
            .overlay(alignment: .bottom) { gradientScrim }
            .overlay(alignment: .bottomLeading) {
                overlay()
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var heroImage: some View {
        LazyImage(url: imageURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if state.isLoading {
                loadingPlaceholder
            } else if let fallbackImageURL {
                // Primary failed — try the fallback URL (e.g. primary poster).
                LazyImage(url: fallbackImageURL) { primaryState in
                    if let image = primaryState.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        fallbackGradient
                    }
                }
            } else {
                fallbackGradient
            }
        }
    }

    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                ProgressView()
                    .tint(.white)
            }
    }

    private var gradientScrim: some View {
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

    private var fallbackGradient: some View {
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
