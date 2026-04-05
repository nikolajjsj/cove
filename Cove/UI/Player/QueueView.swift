import ImageService
import Models
import PlaybackEngine
import SwiftUI
import JellyfinProvider

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
            LazyImage(url: artworkURL(for: track)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
            LazyImage(url: artworkURL(for: track)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
                Text(formatTime(duration))
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
        let item = MediaItem(
            id: albumId,
            title: "",
            mediaType: .album
        )
        return appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 96, height: 96)
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

#Preview {
    QueueView()
}
