import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI
import MediaServerKit

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

                MediaImage.trackThumbnail(url: artworkURL(for: track), cornerRadius: 0)
                    .frame(width: 48, height: 48)

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
        return appState.provider.imageURL(
            for: albumId, type: .primary, maxSize: CGSize(width: 96, height: 96))
    }
}
