import Models
import SwiftUI

/// A reusable row layout for displaying media items in lists.
///
/// Provides a consistent horizontal layout: poster thumbnail → title/subtitle/metadata → trailing content.
/// The thumbnail automatically adapts its aspect ratio based on the media type (square for music, portrait for video).
///
/// ```swift
/// // Simple row (search results):
/// MediaItemRow(
///     imageURL: url,
///     title: item.title,
///     subtitle: "2024 · Movie",
///     mediaType: .movie
/// )
///
/// // Rich row with trailing content (filmography):
/// MediaItemRow(
///     imageURL: url,
///     title: item.title,
///     subtitle: "Breaking Bad · S2E4",
///     mediaType: .episode,
///     metadata: ["2009", "TV-MA", "47m"]
/// ) {
///     RatingBadge(rating: 8.5)
///     Image(systemName: "chevron.right")
/// }
/// ```
struct MediaItemRow<Trailing: View>: View {

    // MARK: - Configuration

    /// The remote image URL for the poster thumbnail.
    let imageURL: URL?

    /// The primary title text.
    let title: String

    /// An optional subtitle displayed below the title.
    let subtitle: String?

    /// The media type, used to determine thumbnail aspect ratio and placeholder icon.
    let mediaType: MediaType

    /// Optional metadata strings displayed as dot-separated text below the subtitle.
    var metadata: [String] = []

    /// The width of the thumbnail. Height is derived from aspect ratio.
    var thumbnailWidth: CGFloat = 56

    /// Trailing content (rating badge, chevron, duration, etc.).
    @ViewBuilder var trailing: () -> Trailing

    // MARK: - Body
    
    var aspectRatio: Double {
        if mediaType.isMusic {
            return 1.0
        } else if mediaType == .episode {
            return 16 / 9
        } else {
            return 2.0 / 3.0
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            MediaImage.poster(
                url: imageURL,
                aspectRatio: aspectRatio,
                icon: mediaType.placeholderIcon,
                cornerRadius: 6
            )
            .frame(
                width: thumbnailWidth,
                height: mediaType.isMusic ? thumbnailWidth : thumbnailWidth * 1.5
            )
            .clipped()

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !metadata.isEmpty {
                    DotSeparatedText(
                        parts: metadata,
                        font: .caption,
                        foregroundStyle: .tertiary
                    )
                }
            }

            Spacer(minLength: 0)

            trailing()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Convenience Init (No Trailing)

extension MediaItemRow where Trailing == EmptyView {

    /// Creates a row with no trailing content.
    init(
        imageURL: URL?,
        title: String,
        subtitle: String?,
        mediaType: MediaType,
        metadata: [String] = [],
        thumbnailWidth: CGFloat = 56
    ) {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.mediaType = mediaType
        self.metadata = metadata
        self.thumbnailWidth = thumbnailWidth
        self.trailing = { EmptyView() }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Simple Row") {
        List {
            MediaItemRow(
                imageURL: nil,
                title: "The Shawshank Redemption",
                subtitle: "1994 · Movie",
                mediaType: .movie
            )

            MediaItemRow(
                imageURL: nil,
                title: "Breaking Bad",
                subtitle: "2008–2013",
                mediaType: .series,
                metadata: ["TV-MA"]
            )

            MediaItemRow(
                imageURL: nil,
                title: "Abbey Road",
                subtitle: "The Beatles",
                mediaType: .album
            )
        }
    }

    #Preview("Rich Row with Trailing") {
        List {
            MediaItemRow(
                imageURL: nil,
                title: "Inception",
                subtitle: nil,
                mediaType: .movie,
                metadata: ["2010", "PG-13", "2h 28m"]
            ) {
                RatingBadge(rating: 8.8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.quaternary)
            }
        }
    }
#endif
