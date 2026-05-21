import Models
import SwiftUI

// MARK: - Next Episode Countdown

/// A floating card shown near the end of an episode, counting down to
/// auto-play of the next episode. Provides dismiss and "Play Now" actions.
struct NextEpisodeCountdownView: View {
    let next: MediaItem
    let countdown: Int
    let thumbnailURL: URL?
    let onDismiss: () -> Void
    let onPlayNow: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Up Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)

                        Spacer()

                        Button("Dismiss", systemImage: "xmark", action: onDismiss)
                            .labelStyle(.iconOnly)
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                            .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 6)
                            .frame(width: 100)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text("Starting in \(countdown)s")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .monospacedDigit()
                        }
                    }

                    Button {
                        onPlayNow()
                    } label: {
                        Text("Play Now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.white, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(width: 280)
                .background(
                    .ultraThinMaterial.opacity(0.8), in: .rect(cornerRadius: 14)
                )
                .environment(\.colorScheme, .dark)
            }
            .padding(24)
        }
    }
}
