import ImageService
import Models
import PlaybackEngine
import SwiftUI
import JellyfinProvider

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0
    @State private var showQueue = false

    var body: some View {
        let player = appState.audioPlayer
        let queue = player.queue

        NavigationStack {
            Group {
                if let track = queue.currentTrack {
                    ScrollView {
                        VStack(spacing: 32) {
                            Spacer()
                                .frame(height: 8)

                            // MARK: - Album Artwork

                            artworkView(for: track)

                            // MARK: - Track Info

                            trackInfoSection(track: track)

                            // MARK: - Progress Bar

                            progressSection(player: player)

                            // MARK: - Playback Controls

                            playbackControls(player: player, queue: queue)

                            // MARK: - Secondary Controls

                            secondaryControls(queue: queue)

                            Spacer()
                                .frame(height: 16)
                        }
                        .padding(.horizontal, 32)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    ContentUnavailableView(
                        "Nothing Playing",
                        systemImage: "music.note",
                        description: Text("Select a track to start listening.")
                    )
                }
            }
            .background(
                backgroundGradient
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .fontWeight(.semibold)
                    }
                    .tint(.primary)
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(for track: Track) -> some View {
        LazyImage(url: artworkURL(for: track)) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else if state.isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ProgressView() }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.3), value: track.id)
    }

    // MARK: - Track Info

    @ViewBuilder
    private func trackInfoSection(track: Track) -> some View {
        VStack(spacing: 6) {
            Text(track.title)
                .font(.title2.bold())
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let artistName = track.artistName {
                Text(artistName)
                    .font(.title3)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let albumName = track.albumName {
                Text(albumName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: track.id)
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressSection(player: AudioPlaybackManager) -> some View {
        let displayTime = isSeeking ? seekTime : player.currentTime
        let totalDuration = player.duration

        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { newValue in
                        if !isSeeking {
                            isSeeking = true
                        }
                        seekTime = newValue
                    }
                ),
                in: 0...max(totalDuration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: seekTime)
                        isSeeking = false
                    }
                }
            )
            .tint(.primary)

            HStack {
                Text(formatTime(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-\(formatTime(max(totalDuration - displayTime, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls(player: AudioPlaybackManager, queue: PlayQueue) -> some View {
        HStack(spacing: 40) {
            // Previous
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(queue.hasPrevious ? .primary : .tertiary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasPrevious)

            // Play / Pause
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: player.isPlaying)

            // Next
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(queue.hasNext ? .primary : .tertiary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasNext)
        }
        .tint(.primary)
    }

    // MARK: - Secondary Controls

    @ViewBuilder
    private func secondaryControls(queue: PlayQueue) -> some View {
        HStack(spacing: 48) {
            // Shuffle
            Button {
                queue.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(queue.shuffleEnabled ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: queue.shuffleEnabled)

            // Repeat
            Button {
                queue.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIconName(for: queue.repeatMode))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(queue.repeatMode != .off ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: queue.repeatMode)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundGradient: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
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
            maxSize: CGSize(width: 600, height: 600)
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func repeatIconName(for mode: RepeatMode) -> String {
        switch mode {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }
}

#Preview {
    AudioPlayerView()
}
