import Models
import PlaybackEngine
import SwiftUI

/// A prominent full-width play/resume button for media detail views.
///
/// Displays "Play" for unwatched items or "Resume at HH:MM:SS" for
/// items with existing progress. Shows a loading indicator while the
/// player is initializing.
///
/// When the item has a resume position, the button's background visually
/// fills from the leading edge with the accent color to reflect how far
/// through the content the user has watched. The unwatched portion uses
/// a subdued tint so the button itself acts as a progress indicator.
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
            .padding(.vertical, 12)
        }
        .buttonStyle(ProgressFillButtonStyle(progress: playbackProgress))
        .disabled(coordinator.isLoadingItem(item.id))
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
    /// which keeps the button fully filled with the accent color.
    private var playbackProgress: Double? {
        guard let position = item.userData?.playbackPosition, position > 0,
            let runtime = item.runtime, runtime > 0
        else { return nil }
        return min(position / runtime, 1.0)
    }
}

// MARK: - Progress Fill Button Style

/// A button style that doubles as a progress indicator.
///
/// When `progress` is `nil` the button renders as a standard filled
/// button in the accent color. When a progress value is provided, the
/// background splits into a vibrant leading portion (watched) and a
/// muted trailing portion (unwatched), giving users an immediate,
/// integrated sense of their playback position.
private struct ProgressFillButtonStyle: ButtonStyle {
    let progress: Double?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background { progressBackground }
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder
    private var progressBackground: some View {
        if let progress {
            ZStack(alignment: .leading) {
                // Muted base spanning the full width (unwatched portion)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.3))

                // Vibrant fill scaled to the watched fraction.
                // Because Color fills the entire available space during
                // layout, scaleEffect compresses it visually from the
                // leading edge without affecting the surrounding layout.
                Color.accentColor
                    .scaleEffect(x: max(progress, 0.0), anchor: .leading)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
            .clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor)
        }
    }
}
