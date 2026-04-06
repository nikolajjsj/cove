import Models
import SwiftUI

/// A landscape card for video content like special features and trailers.
///
/// Displays a 16:9 thumbnail with a title and optional runtime subtitle.
struct LandscapeMediaCard: View {
    let item: MediaItem
    let thumbnailURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 16:9 thumbnail
            ZStack(alignment: .bottomTrailing) {
                MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 8)

                // Runtime badge
                if let runtime = item.runtime, runtime > 0 {
                    Text(TimeFormatting.duration(runtime))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.7))
                        )
                        .padding(6)
                }
            }
            .frame(width: 220)

            // Title
            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(width: 220)
    }
}
