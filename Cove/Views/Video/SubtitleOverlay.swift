import PlaybackEngine
import SwiftUI

// MARK: - Subtitle Overlay

/// Reads `videoManager.currentSubtitleText` in its own `@Observable` tracking
/// scope so that subtitle text changes don't invalidate `VideoPlayerView.body`.
struct SubtitleOverlay: View {
    let videoManager: VideoPlaybackManager
    let subtitleSize: SubtitleSize
    let subtitleColor: SubtitleColor
    let subtitleBackground: SubtitleBackground

    var body: some View {
        if let subtitleText = videoManager.currentSubtitleText {
            VStack {
                Spacer()
                SubtitleTextView(
                    text: subtitleText,
                    size: subtitleSize,
                    color: subtitleColor,
                    background: subtitleBackground
                )
                .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
        }
    }
}
