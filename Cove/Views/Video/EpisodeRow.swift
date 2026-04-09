import ImageService
import Models
import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    let thumbnailURL: URL?
    let progress: Double?  // 0.0–1.0
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 12) {
                // MARK: - Thumbnail

                thumbnailView

                // MARK: - Episode Info

                VStack(alignment: .leading, spacing: 4) {
                    // Episode number badge + title
                    HStack(spacing: 6) {
                        if let number = episode.episodeNumber {
                            Text("E\(number)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor)
                                )
                        }

                        Text(episode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    // Overview
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    // Runtime
                    if let runtime = episode.runtime, runtime > 0 {
                        Text(TimeFormatting.longDuration(runtime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .bottom) {
            MediaImage.videoThumbnail(url: thumbnailURL)
                .aspectRatio(16/9, contentMode: .fit)

            if let progress, progress > 0 {
                VideoProgressOverlay(progress: progress)
            }
        }
    }
}
