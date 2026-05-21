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

    // MARK: - Player Bottom Bar

    /// The bottom bar composes time-dependent children (slider, labels) and
    /// time-independent children (menus) as separate `View` structs so that
    /// rapid `currentTime` ticks don't cause menu re-renders.
    struct PlayerBottomBar: View {
        let item: MediaItem
        let streamInfo: StreamInfo
        let videoManager: VideoPlaybackManager
        let coordinator: VideoPlayerCoordinator
        let authManager: AuthManager
        @Binding var isSeeking: Bool
        @Binding var seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval
        @Binding var showSubtitleSearch: Bool
        let onControlsInteraction: StableAction

        var body: some View {
            VStack(spacing: 8) {
                PlayerSeekSlider(
                    videoManager: videoManager,
                    isSeeking: $isSeeking,
                    seekTime: $seekTime,
                    isGestureSeeking: isGestureSeeking,
                    gestureSeekTime: gestureSeekTime
                )

                HStack(spacing: 12) {
                    PlayerTimeLabels(
                        videoManager: videoManager,
                        isSeeking: isSeeking,
                        seekTime: seekTime,
                        isGestureSeeking: isGestureSeeking,
                        gestureSeekTime: gestureSeekTime
                    )

                    Spacer()

                    PlayerMenuBar(
                        item: item,
                        streamInfo: streamInfo,
                        videoManager: videoManager,
                        coordinator: coordinator,
                        authManager: authManager,
                        showSubtitleSearch: $showSubtitleSearch,
                        onControlsInteraction: onControlsInteraction
                    )
                }
            }
        }
    }

#endif
