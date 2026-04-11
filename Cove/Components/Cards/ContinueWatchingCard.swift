import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// A landscape 16:9 card showing a video thumbnail with a progress bar overlay.
///
/// Used in "Continue Watching" rails to show partially-watched movies and episodes
/// with their current progress and remaining time.
struct ContinueWatchingCard: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop / thumbnail image (landscape 16:9)
                MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 8)
                    .frame(width: 240)

                // Progress bar overlay at the bottom
                if let progress = watchProgress {
                    VideoProgressOverlay(progress: progress, trackHeight: 4)
                        .frame(width: 240)
                        .clipShape(.rect(cornerRadius: 8))
                }

                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // Episode metadata (e.g. "S2 E5 · Breaking Bad") or remaining time
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

    /// Real watch progress computed from `playbackPosition / runtime`.
    private var watchProgress: Double? {
        guard let position = item.userData?.playbackPosition, position > 0,
            let runtime = item.runtime, runtime > 0
        else { return nil }
        return min(max(position / runtime, 0.01), 0.99)
    }

    /// Builds a subtitle like "S2 E5 · Breaking Bad — 42 min remaining"
    /// or just "42 min remaining" for movies.
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

        // Remaining time
        if let position = item.userData?.playbackPosition, position > 0,
            let runtime = item.runtime, runtime > 0
        {
            let remaining = max(runtime - position, 0)
            let minutes = Int(remaining) / 60
            if minutes > 0 {
                parts.append("\(minutes) min remaining")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}
