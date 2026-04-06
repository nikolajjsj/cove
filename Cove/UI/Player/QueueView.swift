import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// Queue view used as Page 3 of the paged player.
/// Shows the current track, play context, and up-next tracks with
/// swipe-to-delete and drag-to-reorder.
struct QueueView: View {
    @Environment(AppState.self) private var appState
    @State private var showClearConfirmation = false

    var body: some View {
        let player = appState.audioPlayer
        let queue = player.queue

        Group {
            if queue.tracks.isEmpty {
                ContentUnavailableView(
                    "Queue Empty",
                    systemImage: "music.note.list",
                    description: Text("Add some tracks to get started.")
                )
            } else {
                queueList(player: player, queue: queue)
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

    // MARK: - Queue List

    @ViewBuilder
    private func queueList(player: AudioPlaybackManager, queue: PlayQueue) -> some View {
        List {
            // MARK: Playing From

            if let context = queue.context {
                Section {
                    playingFromRow(context: context)
                }
            }

            // MARK: Now Playing

            if let currentTrack = queue.currentTrack {
                Section {
                    nowPlayingRow(track: currentTrack, isPlaying: player.isPlaying)
                } header: {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Up Next

            let upNext = queue.upNext
            if !upNext.isEmpty {
                Section {
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, track in
                        trackRow(track: track)
                    }
                    .onDelete { offsets in
                        deleteUpNextTracks(at: offsets, queue: queue)
                    }
                    .onMove { source, destination in
                        moveUpNextTracks(from: source, to: destination, queue: queue)
                    }
                } header: {
                    HStack {
                        Text("Up Next")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)

                        Text("· \(upNext.count) \(upNext.count == 1 ? "track" : "tracks")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear") {
                            showClearConfirmation = true
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Playing From Row

    @ViewBuilder
    private func playingFromRow(context: PlayContext) -> some View {
        HStack(spacing: 8) {
            Image(systemName: contextIcon(for: context.type))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Playing from ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                + Text(context.title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Spacer()

            if context.id != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.white.opacity(0.06))
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

    // MARK: - Now Playing Row

    @ViewBuilder
    private func nowPlayingRow(track: Track, isPlaying: Bool) -> some View {
        HStack(spacing: 12) {
            MediaImage.trackThumbnail(url: artworkURL(for: track))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body.bold())
                    .lineLimit(1)
                    .foregroundStyle(Color.accentColor)

                if let artistName = track.artistName {
                    Text(artistName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.accentColor.opacity(0.1))
        .deleteDisabled(true)
        .moveDisabled(true)
    }

    // MARK: - Track Row

    @ViewBuilder
    private func trackRow(track: Track) -> some View {
        HStack(spacing: 12) {
            MediaImage.trackThumbnail(url: artworkURL(for: track))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let artistName = track.artistName {
                    Text(artistName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }

            Spacer()

            if let duration = track.duration {
                Text(TimeFormatting.playbackPosition(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.4))
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func deleteUpNextTracks(at offsets: IndexSet, queue: PlayQueue) {
        for offset in offsets.sorted().reversed() {
            let absoluteIndex = queue.currentIndex + 1 + offset
            queue.remove(at: absoluteIndex)
        }
    }

    private func moveUpNextTracks(from source: IndexSet, to destination: Int, queue: PlayQueue) {
        guard let sourceIndex = source.first else { return }
        let absoluteSource = queue.currentIndex + 1 + sourceIndex
        let absoluteDestination = queue.currentIndex + 1 + destination
        queue.move(from: absoluteSource, to: absoluteDestination)
    }

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
        guard let albumId = track.albumId else { return nil }
        return appState.provider.imageURL(
            for: albumId, type: .primary, maxSize: CGSize(width: 96, height: 96))
    }
}

#Preview {
    QueueView()
}
