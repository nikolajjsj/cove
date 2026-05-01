import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct NowPlayingBar: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Binding var showFullPlayer: Bool

    let track: Track

    var body: some View {
        Button {
            showFullPlayer = true
        } label: {
            VStack(spacing: 0) {
                // MARK: - Progress Bar

                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

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

                    HStack {
                        Button {
                            appState.audioPlayer.togglePlayPause()
                        } label: {
                            Image(
                                systemName: appState.audioPlayer.isPlaying
                                    ? "pause.fill" : "play.fill"
                            )
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // MARK: - Next Track Button

                        Button {
                            appState.audioPlayer.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.35, bounce: 0.2), value: track.id)
    }

    // MARK: - Helpers

    private var progressFraction: CGFloat {
        let duration = appState.audioPlayer.duration
        guard duration > 0 else { return 0 }
        return CGFloat(appState.audioPlayer.currentTime / duration)
    }

    private func artworkURL(for track: Track) -> URL? {
        return authManager.provider.artworkURL(for: track, maxSize: CGSize(width: 96, height: 96))
    }
}
