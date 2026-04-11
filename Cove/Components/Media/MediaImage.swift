import ImageService
import SwiftUI

/// A reusable image view that wraps `LazyImage` with a consistent placeholder
/// pattern used throughout the app.
///
/// Replaces the many copy-pasted `LazyImage { state in … }` blocks scattered
/// across album cards, track rows, episode thumbnails, poster cards, etc.
///
/// ```swift
/// // Square music artwork
/// MediaImage(url: albumArtURL, placeholderIcon: "music.note", cornerRadius: 8)
///
/// // 16:9 video thumbnail
/// MediaImage(url: thumbURL, aspectRatio: 16.0 / 9.0, placeholderIcon: "play.rectangle")
///
/// // Small track thumbnail with fixed size
/// MediaImage(url: artURL, placeholderIcon: "music.note", placeholderIconFont: .caption2, cornerRadius: 6)
///     .frame(width: 40, height: 40)
///
/// // Poster card with caller-controlled aspect ratio
/// MediaImage(url: posterURL, aspectRatio: posterAspectRatio, contentMode: .fit, placeholderIcon: icon)
/// ```
struct MediaImage: View {

    // MARK: - Configuration

    /// The remote image URL to load. `nil` renders the placeholder immediately.
    let url: URL?

    /// The aspect ratio applied to the image and its placeholder.
    /// Pass `nil` to let the container dictate the size (e.g. via `.frame()`).
    var aspectRatio: CGFloat? = 1

    /// How the image fills its aspect-ratio frame.
    var contentMode: ContentMode = .fill

    /// SF Symbol name shown when the image fails to load or the URL is `nil`.
    var placeholderIcon: String = "photo"

    /// Font size for the placeholder icon. Adjust for small thumbnails vs. large cards.
    var placeholderIconFont: Font = .largeTitle

    /// Corner radius applied via `RoundedRectangle` clip shape.
    /// Pass `0` for no rounding.
    var cornerRadius: CGFloat = 0

    /// Whether to show a `ProgressView` spinner while loading.
    var showsLoadingIndicator: Bool = true

    // MARK: - Body

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .maybeAspectRatio(aspectRatio, contentMode: contentMode)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.primary.opacity(0.4), lineWidth: 1)
                    }
            } else if state.isLoading {
                placeholder
                    .overlay {
                        if showsLoadingIndicator {
                            ProgressView()
                        }
                    }
            } else {
                placeholder
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(placeholderIconFont)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    // MARK: - Private

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .maybeAspectRatio(aspectRatio, contentMode: contentMode)
    }
}

// MARK: - Conditional Aspect Ratio

extension View {
    /// Applies `aspectRatio(_:contentMode:)` only when a non-nil ratio is provided.
    @ViewBuilder
    fileprivate func maybeAspectRatio(_ ratio: CGFloat?, contentMode: ContentMode) -> some View {
        if let ratio {
            self.aspectRatio(ratio, contentMode: contentMode)
        } else {
            self
        }
    }
}

// MARK: - Convenience Initializers

extension MediaImage {

    /// A square music artwork image with rounded corners and shadow-ready styling.
    ///
    /// ```swift
    /// MediaImage.artwork(url: albumURL)
    /// ```
    static func artwork(url: URL?, cornerRadius: CGFloat = 8) -> MediaImage {
        MediaImage(
            url: url,
            aspectRatio: 1,
            placeholderIcon: "music.note",
            cornerRadius: cornerRadius
        )
    }

    /// A small track-row thumbnail (typically 40×40).
    ///
    /// Apply `.frame(width:height:)` at the call-site to set the exact size.
    ///
    /// ```swift
    /// MediaImage.trackThumbnail(url: artURL)
    ///     .frame(width: 40, height: 40)
    /// ```
    static func trackThumbnail(url: URL?, cornerRadius: CGFloat = 6) -> MediaImage {
        MediaImage(
            url: url,
            aspectRatio: 1,
            placeholderIcon: "music.note",
            placeholderIconFont: .caption2,
            cornerRadius: cornerRadius,
            showsLoadingIndicator: false
        )
    }

    /// A 16∶9 landscape video thumbnail.
    ///
    /// ```swift
    /// MediaImage.videoThumbnail(url: episodeThumbURL)
    /// ```
    static func videoThumbnail(url: URL?, cornerRadius: CGFloat = 0) -> MediaImage {
        MediaImage(
            url: url,
            aspectRatio: 16.0 / 9.0,
            placeholderIcon: "play.rectangle",
            placeholderIconFont: .title3,
            cornerRadius: cornerRadius
        )
    }

    /// A poster-style card with a caller-supplied aspect ratio and icon.
    ///
    /// ```swift
    /// MediaImage.poster(url: posterURL, aspectRatio: 2/3, icon: "film")
    /// ```
    static func poster(
        url: URL?,
        aspectRatio: CGFloat = 2.0 / 3.0,
        icon: String = "film",
        cornerRadius: CGFloat = 0
    ) -> MediaImage {
        MediaImage(
            url: url,
            aspectRatio: aspectRatio,
            contentMode: .fit,
            placeholderIcon: icon,
            cornerRadius: cornerRadius
        )
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("MediaImage Variants") {
        ScrollView {
            VStack(spacing: 24) {
                // Square artwork
                MediaImage.artwork(url: nil)
                    .frame(width: 200)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                // Small track thumbnail
                MediaImage.trackThumbnail(url: nil)
                    .frame(width: 40, height: 40)

                // Video thumbnail
                MediaImage.videoThumbnail(url: nil)
                    .frame(width: 300)

                // Custom configuration
                MediaImage(
                    url: nil,
                    aspectRatio: 4.0 / 3.0,
                    placeholderIcon: "person.fill",
                    placeholderIconFont: .title,
                    cornerRadius: 12
                )
                .frame(width: 200)
            }
            .padding()
        }
    }
#endif
