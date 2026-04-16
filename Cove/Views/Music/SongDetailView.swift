import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// A detail view for a single song/track.
///
/// Displays album artwork, song title, artist, album name, duration,
/// genre information, and audio quality details. Provides actions to
/// play, queue, start a radio mix, add to playlist, and navigate to
/// the parent album or artist.
struct SongDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var playlistTrackIds: [ItemID]?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                songHeader
                    .padding(.bottom, 20)

                actionButtons
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                Divider()
                    .padding(.horizontal)

                detailSections
                    .padding(.top, 16)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(item.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    queueActions
                    Divider()
                    radioButton
                    addToPlaylistButton
                    Divider()
                    navigationActions
                    Divider()
                    FavoriteToggle(itemId: item.id, userData: item.userData)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: showPlaylistPickerBinding) {
            PlaylistPickerSheet(trackIds: playlistTrackIds ?? [])
        }
    }

    // MARK: - Header

    private var songHeader: some View {
        VStack(spacing: 16) {
            MediaImage.artwork(url: artworkURL, cornerRadius: 12)
                .frame(width: 280, height: 280)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Text(item.title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let artistName = item.artistName {
                Text(artistName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            songMetadata
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var songMetadata: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            DotSeparatedText(
                parts: parts,
                font: .subheadline,
                foregroundStyle: .secondary
            )
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []

        if let albumName = item.albumName {
            parts.append(albumName)
        }

        if let duration = item.runtime, duration > 0 {
            parts.append(TimeFormatting.trackTime(duration))
        }

        if let genre = item.genres?.first {
            parts.append(genre)
        }

        return parts
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                playSong()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Button {
                appState.audioPlayer.queue.addNext(item.asTrack)
                ToastManager.shared.show(
                    "Playing Next",
                    icon: "text.line.first.and.arrowtriangle.forward"
                )
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Detail Sections

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Album navigation
            if let albumId = item.albumId {
                NavigationLink(
                    value: MediaItem(
                        id: albumId,
                        title: item.albumName ?? "Album",
                        mediaType: .album
                    )
                ) {
                    HStack(spacing: 12) {
                        MediaImage.artwork(url: albumArtworkURL, cornerRadius: 8)
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Album")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.albumName ?? "Unknown Album")
                                .font(.body)
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }

            // Audio info section
            audioInfoSection
        }
    }

    @ViewBuilder
    private var audioInfoSection: some View {
        let infoParts = audioInfoParts
        if !infoParts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Info")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(infoParts.enumerated(), id: \.offset) { index, part in
                        HStack {
                            Text(part.label)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(part.value)
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if index < infoParts.count - 1 {
                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar Menu Actions

    @ViewBuilder
    private var queueActions: some View {
        Button {
            appState.audioPlayer.queue.addNext(item.asTrack)
            ToastManager.shared.show(
                "Playing Next",
                icon: "text.line.first.and.arrowtriangle.forward"
            )
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            appState.audioPlayer.queue.addToEnd(item.asTrack)
            ToastManager.shared.show(
                "Added to Up Next",
                icon: "text.line.last.and.arrowtriangle.forward"
            )
        } label: {
            Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
    }

    private var radioButton: some View {
        Button {
            Task { await appState.startRadio(for: item.id) }
        } label: {
            Label("Radio", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    private var addToPlaylistButton: some View {
        Button {
            playlistTrackIds = [item.id]
        } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }
    }

    @ViewBuilder
    private var navigationActions: some View {
        if let albumId = item.albumId {
            Button {
                let album = MediaItem(
                    id: albumId,
                    title: item.albumName ?? "",
                    mediaType: .album
                )
                appState.navigate(to: .music, destination: album)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
    }

    // MARK: - Playlist Sheet

    private var showPlaylistPickerBinding: Binding<Bool> {
        Binding(
            get: { playlistTrackIds != nil },
            set: { if !$0 { playlistTrackIds = nil } }
        )
    }

    // MARK: - Playback

    private func playSong() {
        let track = item.asTrack
        appState.audioPlayer.play(tracks: [track], startingAt: 0)
    }

    // MARK: - Audio Info Helpers

    private var audioInfoParts: [AudioInfoRow] {
        var parts: [AudioInfoRow] = []

        // Extract audio stream details from mediaStreams if available
        if let streams = item.mediaStreams {
            if let audioStream = streams.first(where: { $0.type == .audio }) {
                if let codec = audioStream.codec {
                    parts.append(AudioInfoRow(label: "Codec", value: codec.uppercased()))
                }
                if let bitrate = audioStream.bitrate, bitrate > 0 {
                    let kbps = bitrate / 1000
                    parts.append(AudioInfoRow(label: "Bit Rate", value: "\(kbps) kbps"))
                }
                if let channels = audioStream.channels, channels > 0 {
                    parts.append(
                        AudioInfoRow(
                            label: "Channels",
                            value: channels == 1 ? "Mono" : channels == 2 ? "Stereo" : "\(channels) channels"
                        )
                    )
                }
            }
        }

        if let genres = item.genres, !genres.isEmpty {
            parts.append(AudioInfoRow(label: "Genre", value: genres.joined(separator: ", ")))
        }

        if let year = item.productionYear {
            parts.append(AudioInfoRow(label: "Year", value: "\(year)"))
        }

        return parts
    }

    // MARK: - Image Helpers

    private var artworkURL: URL? {
        // Try the song's own image first, fall back to album artwork
        if let albumId = item.albumId {
            return authManager.provider.imageURL(
                for: albumId,
                type: .primary,
                maxSize: CGSize(width: 560, height: 560)
            )
        }
        return authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 560, height: 560)
        )
    }

    private var albumArtworkURL: URL? {
        guard let albumId = item.albumId else { return nil }
        return authManager.provider.imageURL(
            for: albumId,
            type: .primary,
            maxSize: CGSize(width: 112, height: 112)
        )
    }
}

// MARK: - Supporting Types

private struct AudioInfoRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

// MARK: - Preview

#Preview {
    let state = AppState.preview
    NavigationStack {
        SongDetailView(
            item: MediaItem(
                id: ItemID("preview-song"),
                title: "Come Together",
                mediaType: .track,
                productionYear: 1969,
                genres: ["Rock"],
                runTimeTicks: 2_590_000_000,
                artistName: "The Beatles",
                albumName: "Abbey Road",
                albumId: ItemID("preview-album")
            )
        )
        .environment(state)
        .environment(state.authManager)
    }
}
