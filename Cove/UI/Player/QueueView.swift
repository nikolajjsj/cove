import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// Queue view used as Page 3 of the paged player.
///
/// Redesigned with a `ScrollView` + `LazyVStack` instead of `List` for full
/// visual control over row backgrounds, separators, and spacing — everything
/// blends seamlessly with the player's dominant-color gradient.
struct QueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var showClearConfirmation = false

    var body: some View {
        let player = appState.audioPlayer
        let queue = player.queue

        Group {
            if queue.tracks.isEmpty {
                emptyState
            } else {
                queueContent(player: player, queue: queue)
            }
        }
        .confirmationDialog(
            "Clear Up Next?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearUpNext(queue: queue)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all upcoming tracks from the queue.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Queue Empty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Add some tracks to get started.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Queue Content

    @ViewBuilder
    private func queueContent(player: AudioPlaybackManager, queue: PlayQueue) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Playing From
                if let context = queue.context {
                    playingFromPill(context: context)
                        .padding(.bottom, 16)
                }

                // Now Playing
                if let currentTrack = queue.currentTrack {
                    nowPlayingSection(track: currentTrack, isPlaying: player.isPlaying)
                }

                // Up Next
                let upNext = queue.upNext
                if !upNext.isEmpty {
                    upNextSection(tracks: upNext, queue: queue)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Playing From

    private func playingFromPill(context: PlayContext) -> some View {
        HStack(spacing: 6) {
            Image(systemName: contextIcon(for: context.type))
                .font(.caption2)

            Text("Playing from")
                .font(.caption)
                + Text(" \(context.title)")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func contextIcon(for type: PlayContextType) -> String {
        switch type {
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "music.mic"
        case .genre: "guitars"
        case .songs: "music.note"
        case .radio: "dot.radiowaves.left.and.right"
        case .unknown: "music.note"
        }
    }

    // MARK: - Now Playing Section

    private func nowPlayingSection(track: Track, isPlaying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            HStack(spacing: 14) {
                MediaImage.trackThumbnail(url: artworkURL(for: track), cornerRadius: 8)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let artistName = track.artistName {
                        Text(artistName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.primary.opacity(0.65))
                    }
                }

                Spacer(minLength: 0)

                // Animated equalizer
                Image(systemName: isPlaying ? "waveform" : "speaker.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.bottom, 20)
    }

    // MARK: - Up Next Section

    private func upNextSection(tracks: [Track], queue: PlayQueue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Up Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("· \(tracks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.7))

                Spacer()

                Button {
                    showClearConfirmation = true
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Track rows
            ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                upNextRow(track: track, offset: offset, queue: queue)
            }
        }
    }

    private func upNextRow(track: Track, offset: Int, queue: PlayQueue) -> some View {
        Button {
            let absoluteIndex = queue.currentIndex + 1 + offset
            appState.audioPlayer.skipTo(index: absoluteIndex)
        } label: {
            HStack(spacing: 12) {
                MediaImage.trackThumbnail(url: artworkURL(for: track), cornerRadius: 6)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let artistName = track.artistName {
                        Text(artistName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)

                if let duration = track.duration {
                    Text(TimeFormatting.trackTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.35))
                }

                // Remove button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        let absoluteIndex = queue.currentIndex + 1 + offset
                        queue.remove(at: absoluteIndex)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func clearUpNext(queue: PlayQueue) {
        let upNextCount = queue.upNext.count
        for _ in 0..<upNextCount {
            let removeIndex = queue.currentIndex + 1
            if queue.tracks.indices.contains(removeIndex) {
                queue.remove(at: removeIndex)
            }
        }
        appState.showToast("Queue cleared", icon: "checkmark.circle.fill")
    }

    // MARK: - Helpers

    private func artworkURL(for track: Track) -> URL? {
        let itemId = track.albumId ?? track.id
        return authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 96, height: 96))
    }
}

#Preview {
    let state = AppState.preview
    QueueView()
        .environment(state)
        .environment(state.authManager)
}
