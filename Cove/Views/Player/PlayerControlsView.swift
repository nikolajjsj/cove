import PlaybackEngine
import SwiftUI

/// Scrubber and transport controls for the full-screen audio player.
///
/// Intentionally minimal — track info, favourites, sleep timer, and the
/// context menu all live in `PlayerTrackInfoRow`. Keeping this view slim
/// ensures the scrubber is always at the same position regardless of which
/// player page is active.
///
/// **Observation isolation:** `ScrubberView` and `PlaybackControlsRow` are
/// separate `struct`s so per-tick `currentTime` and play-state changes only
/// invalidate those small subtrees.
struct PlayerControlsView: View {
    var body: some View {
        VStack(spacing: 15) {
            ScrubberView()
            PlaybackControlsRow()
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Scrubber (Isolated)

private struct ScrubberView: View {
    @Environment(AppState.self) private var appState
    @State private var isSeeking = false
    @State private var scrubPosition: Double = 0

    private var player: AudioPlaybackManager { appState.audioPlayer }

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: $scrubPosition,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        player.seek(to: scrubPosition)
                    }
                }
            )
            .tint(.primary)

            HStack {
                Text(TimeFormatting.playbackPosition(scrubPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-\(TimeFormatting.playbackPosition(max(player.duration - scrubPosition, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: player.currentTime, initial: true) { _, newTime in
            guard !isSeeking else { return }
            scrubPosition = newTime
        }
    }
}

// MARK: - Playback Controls Row (Isolated)

private struct PlaybackControlsRow: View {
    @Environment(AppState.self) private var appState

    private var player: AudioPlaybackManager { appState.audioPlayer }
    private var queue: PlayQueue { player.queue }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                queue.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(queue.shuffleEnabled ? Color.accentColor : .secondary)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(queue.hasPrevious ? .primary : .tertiary)
                    .frame(height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasPrevious)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: player.isPlaying)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(queue.hasNext ? .primary : .tertiary)
                    .frame(height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasNext)
            
            Spacer()

            Button {
                queue.cycleRepeatMode()
            } label: {
                Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(queue.repeatMode != .off ? Color.accentColor : .secondary)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}
