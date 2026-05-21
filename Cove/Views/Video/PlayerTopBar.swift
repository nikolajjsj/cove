import AVKit
import Models
import PlaybackEngine
import SwiftUI

#if !os(tvOS)

    // MARK: - Player Top Bar

    struct PlayerTopBar: View {
        let item: MediaItem
        let videoManager: VideoPlaybackManager
        let onDismiss: () -> Void
        let onShowChapters: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                // Restore orientation eagerly — before the view starts its
                // removal transition — so the device rotates back immediately.
                Button("Close", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = item.playerTopBarSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !item.chapters.isEmpty {
                    Button("Chapters", systemImage: "list.bullet.rectangle", action: onShowChapters)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                }

                // Aspect ratio toggle
                Button(
                    "Aspect Ratio",
                    systemImage: videoManager.videoGravity == .resizeAspectFill
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    action: videoManager.cycleAspectRatio
                )
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)

                #if os(iOS)
                    if videoManager.isPiPPossible {
                        Button(
                            "Picture in Picture",
                            systemImage: videoManager.isPiPActive ? "pip.exit" : "pip.enter",
                            action: videoManager.togglePiP
                        )
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                    }
                #endif
            }
        }
    }

#endif
