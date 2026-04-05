import DownloadManager
import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct AlbumDetailView: View {
    let albumItem: MediaItem
    @Environment(AppState.self) private var appState
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading album…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Album",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        albumHeader
                            .padding(.bottom, 20)

                        actionButtons
                            .padding(.horizontal)
                            .padding(.bottom, 16)

                        Divider()
                            .padding(.horizontal)

                        trackList
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(albumItem.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            //ToolbarItem(placement: .topBarTrailing) {
            ToolbarItem() {
                if let downloadManager = appState.downloadManager {
                    DownloadButton(
                        item: albumItem,
                        serverId: appState.activeConnection?.id.uuidString ?? "",
                        downloadManager: downloadManager
                    ) {
                        try await appState.provider.downloadURL(for: albumItem, profile: nil)
                    }
                }
            }
        }
        .task {
            await loadTracks()
        }
    }

    // MARK: - Album Header

    private var albumHeader: some View {
        VStack(spacing: 16) {
            // Album artwork
            LazyImage(url: albumImageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay { ProgressView() }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 56))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            // Album title
            Text(albumItem.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Artist name
            if let artistName = inferredArtistName {
                Text(artistName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Metadata line: Year • Genre • Tracks • Duration
            albumMetadata
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var albumMetadata: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []

        // Infer year from first track or album overview
        // We don't have year directly on MediaItem, so we skip it unless tracks provide info

        if !tracks.isEmpty {
            let count = tracks.count
            parts.append("\(count) \(count == 1 ? "track" : "tracks")")
        }

        let totalDuration = tracks.compactMap(\.duration).reduce(0, +)
        if totalDuration > 0 {
            parts.append(formatAlbumDuration(totalDuration))
        }

        return parts
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                playAllTracks(startingAt: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(tracks.isEmpty)

            Button {
                playShuffled()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(tracks.isEmpty)
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(groupedByDisc.keys.sorted()), id: \.self) { discNumber in
                if let discTracks = groupedByDisc[discNumber] {
                    // Show disc header only if there are multiple discs
                    if groupedByDisc.count > 1 {
                        discHeader(discNumber)
                    }

                    ForEach(Array(discTracks.enumerated()), id: \.element.id) { localIndex, track in
                        let globalIndex = globalTrackIndex(for: track)
                        TrackRow(
                            track: track,
                            isCurrentTrack: isCurrentTrack(track),
                            isPlaying: isCurrentTrack(track) && appState.audioPlayer.isPlaying
                        ) {
                            playAllTracks(startingAt: globalIndex)
                        }

                        if localIndex < discTracks.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func discHeader(_ discNumber: Int) -> some View {
        HStack {
            Image(systemName: "opticaldisc")
                .foregroundStyle(.secondary)
            Text("Disc \(discNumber)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Disc Grouping

    private var groupedByDisc: [Int: [Track]] {
        Dictionary(grouping: tracks) { $0.discNumber ?? 1 }
    }

    private func globalTrackIndex(for track: Track) -> Int {
        tracks.firstIndex(where: { $0.id == track.id }) ?? 0
    }

    // MARK: - Playback

    private func playAllTracks(startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func playShuffled() {
        guard !tracks.isEmpty else { return }
        var shuffled = tracks
        shuffled.shuffle()
        appState.audioPlayer.play(tracks: shuffled, startingAt: 0)
    }

    private func isCurrentTrack(_ track: Track) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id == track.id
    }

    // MARK: - Data Loading

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            tracks = try await appState.provider.tracks(album: albumItem.id)
        } catch {
            errorMessage = error.localizedDescription
            tracks = []
        }
        isLoading = false
    }

    // MARK: - Image Helpers

    private var albumImageURL: URL? {
        appState.provider.imageURL(
            for: albumItem,
            type: .primary,
            maxSize: CGSize(width: 600, height: 600)
        )
    }

    // MARK: - Inferred Metadata

    private var inferredArtistName: String? {
        // Try to get artist name from the first track
        tracks.first?.artistName
    }

    // MARK: - Duration Formatting

    private func formatAlbumDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Track Row

private struct TrackRow: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track number or now-playing indicator
                Group {
                    if isCurrentTrack {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    } else {
                        Text(trackNumberText)
                            .foregroundStyle(.tertiary)
                            .font(.subheadline)
                    }
                }
                .frame(width: 28, alignment: .trailing)

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .foregroundStyle(isCurrentTrack ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if let artistName = track.artistName {
                        Text(artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Duration
                if let duration = track.duration, duration > 0 {
                    Text(formatTrackDuration(duration))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var trackNumberText: String {
        if let num = track.trackNumber {
            return "\(num)"
        }
        return ""
    }

    private func formatTrackDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AlbumDetailView(
            albumItem: MediaItem(
                id: ItemID("preview-album"),
                title: "Preview Album",
                overview: "A great album",
                mediaType: .album
            )
        )
        .environment(AppState())
    }
}
