import Models
import PlaybackEngine
import SwiftUI

#if !os(tvOS)

    // MARK: - Player Seek Slider

    /// The seek slider, isolated into its own view so that `videoManager.currentTime`
    /// reads happen here instead of in `VideoPlayerView.body`.
    struct PlayerSeekSlider: View {
        let videoManager: VideoPlaybackManager
        @Binding var isSeeking: Bool
        @Binding var seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval

        private var displayTime: TimeInterval {
            if isGestureSeeking { return gestureSeekTime }
            if isSeeking { return seekTime }
            return videoManager.currentTime
        }

        var body: some View {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { newValue in
                        if !isSeeking {
                            isSeeking = true
                        }
                        seekTime = newValue
                    }
                ),
                in: 0...max(videoManager.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        videoManager.seek(to: seekTime)
                        isSeeking = false
                    }
                }
            )
            .tint(.white)
        }
    }

    // MARK: - Player Time Labels

    /// Displays elapsed / total time, isolated so `currentTime` reads don't
    /// propagate up to `VideoPlayerView.body`.
    struct PlayerTimeLabels: View {
        let videoManager: VideoPlaybackManager
        let isSeeking: Bool
        let seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval

        private var displayTime: TimeInterval {
            if isGestureSeeking { return gestureSeekTime }
            if isSeeking { return seekTime }
            return videoManager.currentTime
        }

        var body: some View {
            HStack(spacing: 12) {
                Text(TimeFormatting.playbackPosition(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(TimeFormatting.playbackPosition(videoManager.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

#endif
