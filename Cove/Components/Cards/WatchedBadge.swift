import SwiftUI

/// A small badge overlaid on media artwork to indicate the item has been fully watched.
///
/// Displays a green filled checkmark circle in the corner of a poster or thumbnail.
/// Place this inside a `ZStack(alignment: .topTrailing)` on top of the artwork:
///
/// ```swift
/// ZStack(alignment: .topTrailing) {
///     MediaImage.poster(url: url, cornerRadius: 8)
///     WatchedBadge()
/// }
/// ```
struct WatchedBadge: View {
    /// The SF Symbol font size for the badge icon. Defaults to `.callout`.
    /// Pass `.caption` or `.caption2` for smaller thumbnail contexts.
    var font: Font = .callout

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .green)
            .font(font)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .padding(6)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Watched Badge on Poster") {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.4))
                .frame(width: 130, height: 195)
            WatchedBadge()
        }
        .padding()
    }
#endif
