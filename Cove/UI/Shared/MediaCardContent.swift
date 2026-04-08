import SwiftUI

/// A reusable card content layout used by media cards throughout the app.
///
/// Displays a square artwork image on top with a title and optional subtitle below.
/// This component handles only the visual layout — wrapping in `NavigationLink`,
/// `Button`, or adding `.mediaContextMenu` is the caller's responsibility.
///
/// ```swift
/// // Album card style (2-line title)
/// MediaCardContent(imageURL: url, title: "Abbey Road", subtitle: "The Beatles", titleLineLimit: 2)
///
/// // Song card style (1-line title)
/// MediaCardContent(imageURL: url, title: "Come Together", subtitle: "The Beatles")
/// ```
struct MediaCardContent: View {

    /// The remote image URL for the artwork.
    let imageURL: URL?

    /// The primary title displayed below the artwork.
    let title: String

    /// An optional secondary line displayed below the title.
    let subtitle: String?

    /// Maximum number of lines for the title. Defaults to 1.
    var titleLineLimit: Int = 1

    /// Whether the title reserves space for the full `titleLineLimit` even
    /// when the text is shorter. Useful for keeping grid layouts aligned.
    var reservesSpace: Bool = false

    /// Corner radius applied to the artwork image. Defaults to 8.
    var imageCornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: imageCornerRadius)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(titleLineLimit, reservesSpace: reservesSpace)
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("With Subtitle") {
        MediaCardContent(
            imageURL: nil,
            title: "Abbey Road",
            subtitle: "The Beatles",
            titleLineLimit: 2,
            reservesSpace: true
        )
        .frame(width: 140)
        .padding()
    }

    #Preview("Without Subtitle") {
        MediaCardContent(
            imageURL: nil,
            title: "Come Together",
            subtitle: nil
        )
        .frame(width: 140)
        .padding()
    }
#endif
