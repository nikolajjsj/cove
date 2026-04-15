import Models
import PlaybackEngine
import SwiftUI

/// A prominent full-width play/resume button for media detail views.
///
/// Displays "Play" for unwatched items or "Resume at HH:MM:SS" for
/// items with existing progress. Shows a loading indicator while the
/// player is initializing.
///
/// When the item has a resume position, a thin progress bar is rendered
/// beneath the button to give users an immediate visual sense of how
/// far through the content they are.
///
/// ```swift
/// PlayButton(item: item)
/// ```
struct PlayButton: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                coordinator.play(item: item, using: authManager.provider)
            } label: {
                HStack(spacing: 8) {
                    if coordinator.isLoadingItem(item.id) {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.body)
                    }

                    Text(playButtonLabel)
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(coordinator.isLoadingItem(item.id))

            // Visual progress bar for resume position
            if let progress = playbackProgress {
                ResumeProgressBar(progress: progress)
            }
        }
    }

    // MARK: - Helpers

    private var playButtonLabel: String {
        if let position = item.userData?.playbackPosition, position > 0 {
            return "Resume at \(TimeFormatting.playbackPosition(position))"
        }
        return "Play"
    }

    /// Calculates the playback progress as a fraction from 0.0 to 1.0.
    ///
    /// Returns `nil` when there is no resume position or no runtime,
    /// which hides the progress bar entirely.
    private var playbackProgress: Double? {
        guard let position = item.userData?.playbackPosition, position > 0,
            let runtime = item.runtime, runtime > 0
        else { return nil }
        return min(position / runtime, 1.0)
    }
}

// MARK: - Resume Progress Bar

/// A thin progress bar showing how far through a media item the user has watched.
///
/// Rendered beneath the play button to provide an at-a-glance visual indicator
/// of resume position.
private struct ResumeProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.2))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1.0))
            }
        }
        .frame(height: 4)
        .clipShape(.capsule)
    }
}
