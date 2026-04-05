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
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

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
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    // Runtime
                    if let runtime = episode.runtime, runtime > 0 {
                        Text(formatRuntime(runtime))
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
            LazyImage(url: thumbnailURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .overlay { ProgressView().controlSize(.small) }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }

            // Progress bar overlay at bottom of thumbnail
            if let progress, progress > 0 {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 3)

                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * min(progress, 1.0), height: 3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatRuntime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}
