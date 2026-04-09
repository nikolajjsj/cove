import SwiftUI
import WidgetKit

/// Medium widget showing two items side by side. Tapping a card opens the
/// item's detail view; tapping the play button starts playback immediately.
struct MediumWidgetView: View {
    let items: [WidgetMediaItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.prefix(2)) { item in
                MediumWidgetCard(item: item)
            }
        }
    }
}

/// A single card within the medium widget, filling its share of the
/// horizontal space with a background image and overlaid metadata.
///
/// The card background is a `Link` to the detail view. The play button
/// is a separate `Link` layered on top so WidgetKit's hit-testing
/// routes taps on it to the play URL instead.
private struct MediumWidgetCard: View {
    let item: WidgetMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed background image (falls through to detail link below)
            WidgetBackgroundImage(imageData: item.imageData)

            // Gradient covering the lower portion for text legibility
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.4), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            // Detail-view link covering the full card area
            Link(destination: item.deepLinkURL) {
                Color.clear
            }

            // Text content — extra trailing padding so it doesn't overlap the play button
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
    }
}
