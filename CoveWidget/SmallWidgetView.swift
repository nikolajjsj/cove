import SwiftUI
import WidgetKit

/// Small widget showing a single item with a full-bleed background image.
/// Tapping the widget opens the item's detail view; tapping the play
/// button in the corner starts playback immediately.
struct SmallWidgetView: View {
    let item: WidgetMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed background image (no Link — falls through to widgetURL)
            WidgetBackgroundImage(imageData: item.imageData)

            // Gradient covering the lower half for text legibility
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.4), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            // Text content — padded with extra trailing space for the play button
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                Text(item.seriesName ?? item.title)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                if let label = item.seasonEpisodeLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let progress = item.playbackProgress {
                    ProgressView(value: progress)
                        .tint(.white)
                }
            }
            .padding()
            .padding(.trailing, 32)

            // Play button — separate Link so only this triggers playback
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Link(destination: item.playURL) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                }
            }
            .padding()
        }
        .widgetURL(item.deepLinkURL)
    }
}
