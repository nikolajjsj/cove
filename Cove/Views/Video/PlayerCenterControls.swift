import Defaults
import Models
import PlaybackEngine
import SwiftUI

#if !os(tvOS)

    // MARK: - Player Center Controls

    struct PlayerCenterControls: View {
        let videoManager: VideoPlaybackManager
        @Binding var backwardSkipTrigger: Int
        @Binding var forwardSkipTrigger: Int
        let onSkipBackward: () -> Void
        let onSkipForward: () -> Void
        let onResetTimer: () -> Void

        private var skipBackwardIcon: String {
            "gobackward.\(Int(Defaults[.skipBackwardInterval]))"
        }

        private var skipForwardIcon: String {
            "goforward.\(Int(Defaults[.skipForwardInterval]))"
        }

        var body: some View {
            HStack(spacing: 48) {
                Button {
                    backwardSkipTrigger += 1
                    onSkipBackward()
                    onResetTimer()
                } label: {
                    Label("Skip Back", systemImage: skipBackwardIcon)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: backwardSkipTrigger)
                        .frame(width: 56, height: 56)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button {
                    videoManager.togglePlayPause()
                    onResetTimer()
                } label: {
                    Label(
                        videoManager.isPlaying ? "Pause" : "Play",
                        systemImage: videoManager.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button {
                    forwardSkipTrigger += 1
                    onSkipForward()
                    onResetTimer()
                } label: {
                    Label("Skip Forward", systemImage: skipForwardIcon)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: forwardSkipTrigger)
                        .frame(width: 56, height: 56)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if videoManager.nextEpisode != nil && !videoManager.showNextEpisodeCountdown {
                    Button("Next Episode", systemImage: "forward.end.fill") {
                        videoManager.playNextEpisode()
                        onResetTimer()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                }
            }
        }
    }

#endif
