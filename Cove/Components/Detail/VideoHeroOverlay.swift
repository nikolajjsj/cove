import SwiftUI

/// The text overlay rendered inside a `HeroSection` for video detail views.
///
/// Consolidates the duplicated hero content from `MovieDetailView` and
/// `SeriesDetailView`. Both views use an identical VStack of title,
/// optional original title, dot-separated subtitle parts, and optional tagline.
///
/// ```swift
/// HeroSection(imageURL: backdropURL) {
///     VideoHeroOverlay(
///         title: item.title,
///         originalTitle: displayItem.originalTitle,
///         subtitleParts: heroSubtitleParts,
///         tagline: displayItem.tagline
///     )
/// }
/// ```
struct VideoHeroOverlay: View {
    let title: String
    var originalTitle: String? = nil
    var subtitleParts: [String] = []
    var tagline: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
                .bold()
                .foregroundStyle(.primary)

            if let originalTitle,
                !originalTitle.isEmpty,
                originalTitle != title
            {
                Text(originalTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            DotSeparatedText(parts: subtitleParts)

            if let tagline, !tagline.isEmpty {
                TaglineView(tagline: tagline)
            }
        }
    }
}

#if DEBUG
    #Preview("Video Hero Overlay") {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.blue.opacity(0.3), .black.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VideoHeroOverlay(
                title: "The Shawshank Redemption",
                originalTitle: "Die Verurteilten",
                subtitleParts: ["1994", "R", "2h 22m"],
                tagline: "Fear can hold you prisoner. Hope can set you free."
            )
            .padding()
        }
        .frame(height: 400)
    }
#endif
