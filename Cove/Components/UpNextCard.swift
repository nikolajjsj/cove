import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// A landscape 16:9 card showing a video thumbnail with a centered play button overlay.
///
/// Used in "Up Next" rails to surface the next unwatched episode for each series
/// the user is following.
struct UpNextCard: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Episode thumbnail with play button overlay
            ZStack {
                MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 8)

                // Semi-transparent scrim for better play button visibility
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.15))

                // Centered play button
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 2) {
                // Episode title
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // Subtitle: "S2 E5 · Breaking Bad" or runtime for movies
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 240)
        .mediaContextMenu(item: item)
    }

    // MARK: - Helpers

    private var thumbnailURL: URL? {
        // Episodes: Primary is the episode screenshot in Jellyfin.
        // Movies: Backdrop is the widescreen fanart; fall back to Primary (poster).
        switch item.mediaType {
        case .episode:
            return authManager.provider.imageURL(
                for: item, type: .primary, maxSize: CGSize(width: 480, height: 270))
        default:
            return authManager.provider.imageURL(
                for: item, type: .backdrop, maxSize: CGSize(width: 480, height: 270))
                ?? authManager.provider.imageURL(
                    for: item, type: .primary, maxSize: CGSize(width: 480, height: 270))
        }
    }

    /// Builds a subtitle like "S2 E5 · Breaking Bad — 45m" or just "1h 23m" for movies.
    private var subtitleText: String? {
        var parts: [String] = []

        // Episode info
        if item.mediaType == .episode {
            var episodePart = ""
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                episodePart = "S\(s) E\(e)"
            }
            if let series = item.seriesName, !series.isEmpty {
                episodePart += episodePart.isEmpty ? series : " · \(series)"
            }
            if !episodePart.isEmpty {
                parts.append(episodePart)
            }
        }

        // Runtime
        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}
