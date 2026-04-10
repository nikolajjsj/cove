import SwiftUI

/// A progress bar overlay meant to sit at the bottom of a video thumbnail.
///
/// Displays a thin horizontal track with an accent-colored fill representing
/// playback progress. Designed to be layered inside a `ZStack(alignment: .bottom)`
/// on top of a `MediaImage.videoThumbnail`.
///
/// ```swift
/// ZStack(alignment: .bottom) {
///     MediaImage.videoThumbnail(url: thumbURL, cornerRadius: 8)
///     VideoProgressOverlay(progress: 0.45)
/// }
/// ```
struct VideoProgressOverlay: View {
    /// Playback progress from `0.0` to `1.0`. Values outside this range are clamped.
    let progress: Double

    /// Height of the progress track in points.
    var trackHeight: CGFloat = 3

    var body: some View {
        VStack {
            Spacer()
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: trackHeight)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: trackHeight, alignment: .leading)
                    .scaleEffect(x: min(max(progress, 0), 1.0), anchor: .leading)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("50% Progress") {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.gray)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(width: 240)
            VideoProgressOverlay(progress: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    #Preview("80% Progress — Thicker") {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.gray)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(width: 240)
            VideoProgressOverlay(progress: 0.8, trackHeight: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }
#endif
