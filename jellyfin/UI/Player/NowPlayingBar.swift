import ImageService
import Models
import PlaybackEngine
import SwiftUI

struct NowPlayingBar: View {
    @Environment(AppState.self) private var appState
    @Binding var showFullPlayer: Bool

    var body: some View {
        let player = appState.audioPlayer
        let queue = player.queue

        if let track = queue.currentTrack {
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
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 64)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.35, bounce: 0.2), value: track.id)
        }
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

#Preview {
    NowPlayingBar(showFullPlayer: .constant(false))
}
