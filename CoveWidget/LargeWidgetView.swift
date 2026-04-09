import SwiftUI
import WidgetKit

/// Large widget displaying a vertical list of items pinned to the top,
/// with a section header, thumbnails, metadata, progress indicators,
/// and per-row play buttons. Tapping a row opens the detail view;
/// tapping the play button starts playback immediately.
struct LargeWidgetView: View {
    let entry: CoveWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.contentType == .continueWatching ? "Continue Watching" : "Next Up")
                .font(.headline)

            ForEach(entry.items.prefix(5)) { item in
                LargeWidgetRow(item: item)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

/// A single row in the large widget list. The thumbnail and text are
/// wrapped in a `Link` to the detail view; the play button is a
/// separate `Link` that starts playback immediately.
private struct LargeWidgetRow: View {
    let item: WidgetMediaItem

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: item.deepLinkURL) {
                HStack(spacing: 10) {
                    WidgetThumbnailView(imageData: item.imageData, cornerRadius: 4)
                        .frame(width: 64, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.seriesName ?? item.title)
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let label = item.seasonEpisodeLabel {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let progress = item.playbackProgress {
                            ProgressView(value: progress)
                                .tint(.accentColor)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            Link(destination: item.playURL) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.quaternary, in: .circle)
            }
        }
    }
}
