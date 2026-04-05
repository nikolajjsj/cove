import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI
import MediaServerKit

struct QueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let player = appState.audioPlayer
        let queue = player.queue

        NavigationStack {
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
            .navigationTitle("Queue")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Queue List

    @ViewBuilder
    private func queueList(player: AudioPlaybackManager, queue: PlayQueue) -> some View {
        List {
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
                        trackRow(
                            track: track,
                            index: offset + 1
                        )
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
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(upNext.count) track\(upNext.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
            .environment(\.editMode, .constant(.active))
        #endif
    }

    // MARK: - Now Playing Row

    @ViewBuilder
    private func nowPlayingRow(track: Track, isPlaying: Bool) -> some View {
        HStack(spacing: 12) {
            // Animated indicator or artwork thumbnail
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
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Playing indicator
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.accentColor.opacity(0.08))
        .deleteDisabled(true)
        .moveDisabled(true)
    }

    // MARK: - Track Row

    @ViewBuilder
    private func trackRow(track: Track, index: Int) -> some View {
        HStack(spacing: 12) {
            // Small artwork thumbnail
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
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let duration = track.duration {
                Text(TimeFormatting.playbackPosition(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    /// Delete tracks from the Up Next section.
    /// Offsets are relative to the upNext array, so we shift them
    /// to absolute queue indices (currentIndex + 1 + offset).
    private func deleteUpNextTracks(at offsets: IndexSet, queue: PlayQueue) {
        // Remove in reverse order so indices stay valid
        for offset in offsets.sorted().reversed() {
            let absoluteIndex = queue.currentIndex + 1 + offset
            queue.remove(at: absoluteIndex)
        }
    }

    /// Move tracks within the Up Next section.
    /// Source and destination are relative to upNext, so we shift them.
    private func moveUpNextTracks(from source: IndexSet, to destination: Int, queue: PlayQueue) {
        guard let sourceIndex = source.first else { return }
        let absoluteSource = queue.currentIndex + 1 + sourceIndex
        let absoluteDestination = queue.currentIndex + 1 + destination
        queue.move(from: absoluteSource, to: absoluteDestination)
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
