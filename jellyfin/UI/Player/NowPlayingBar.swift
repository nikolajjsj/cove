import ImageService
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

struct NowPlayingBar: View {
    @Environment(AppState.self) private var appState
    @Binding var showFullPlayer: Bool

    let track: Track

    var body: some View {
        Button {
            showFullPlayer = true
        } label: {
            HStack(spacing: 12) {
                // MARK: - Album Artwork

                LazyImage(url: artworkURL(for: track)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // MARK: - Track Info

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let artistName = track.artistName {
                        Text(artistName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // MARK: - Play / Pause Button

                Button {
                    appState.audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: appState.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.35, bounce: 0.2), value: track.id)
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
}
