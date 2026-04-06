import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

#if canImport(MediaPlayer)
    import MediaPlayer
#endif

/// Persistent controls displayed below the paged content in the full-screen player.
///
/// **Observation isolation:** The scrubber and sleep-timer label are extracted
/// into their own `struct` views (`ScrubberView`, `SleepTimerButton`) so that
/// `AudioPlaybackManager.currentTime` / `sleepTimerRemaining` changes only
/// invalidate those small subtrees — not the entire controls view.  This stops
/// context-menus from flickering closed on every playback tick.
struct PlayerControlsView: View {
    let track: Track
    @Binding var currentPage: PlayerPage
    @Environment(AppState.self) private var appState
    @State private var showPlaylistPicker = false
    @State private var showQualityPopover = false

    var body: some View {
        VStack(spacing: 12) {
            // Track Info
            trackInfoRow

            // Scrubber – isolated so tick updates don't invalidate us
            ScrubberView()

            // Playback Controls – isolated so isPlaying changes stay local
            PlaybackControlsRow()

            // Bottom Toolbar
            bottomToolbar
        }
        .padding(.horizontal, 32)
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerSheet(trackIds: [track.id])
        }
    }

    // MARK: - Track Info Row

    private var trackInfoRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let artistName = track.artistName {
                    Text(artistName)
                        .font(.title3)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: track.id)

            // Favorite button
            FavoriteButton(track: track)

            // Context menu
            Menu {
                Button {
                    appState.audioPlayer.queue.addNext(track)
                    appState.showToast("Playing Next", icon: "text.line.first.and.arrowforward")
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowforward")
                }

                Button {
                    appState.audioPlayer.queue.addToEnd(track)
                    appState.showToast("Added to Up Next", icon: "text.line.last.and.arrowforward")
                } label: {
                    Label("Play Later", systemImage: "text.line.last.and.arrowforward")
                }

                Divider()

                Button {
                    showPlaylistPicker = true
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }

                if let albumId = track.albumId {
                    Button {
                        let albumItem = MediaItem(
                            id: ItemID(albumId.rawValue),
                            title: track.albumName ?? "",
                            mediaType: .album
                        )
                        appState.navigate(to: .music, destination: albumItem)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }

                if let artistId = track.artistId {
                    Button {
                        let artistItem = MediaItem(
                            id: ItemID(artistId.rawValue),
                            title: track.artistName ?? "",
                            mediaType: .artist
                        )
                        appState.navigate(to: .music, destination: artistItem)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            // Lyrics shortcut
            Button {
                withAnimation { currentPage = .lyrics }
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.body)
                    .foregroundStyle(currentPage == .lyrics ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()

            // Queue shortcut
            Button {
                withAnimation { currentPage = .queue }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.body)
                    .foregroundStyle(currentPage == .queue ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()

            // Sleep Timer – isolated so remaining-seconds ticks stay local
            SleepTimerButton()

            // Audio quality badge
            if let codec = track.codec {
                Spacer()
                
                Button {
                    showQualityPopover = true
                } label: {
                    Text(codec.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(isLossless(codec) ? Color.accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (isLossless(codec) ? Color.accentColor : Color.secondary).opacity(0.15),
                            in: Capsule()
                        )
                }
                .popover(isPresented: $showQualityPopover) {
                    qualityPopoverContent
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isLossless(_ codec: String) -> Bool {
        let lossless = ["flac", "alac", "wav", "aiff", "dsd", "pcm"]
        return lossless.contains(codec.lowercased())
    }

    @ViewBuilder
    private var qualityPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Quality")
                .font(.headline)

            if let codec = track.codec {
                HStack {
                    Text("Codec")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(codec.uppercased())
                        .fontWeight(.medium)
                }
            }

            if let bitRate = track.bitRate, bitRate > 0 {
                HStack {
                    Text("Bitrate")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(bitRate / 1000) kbps")
                        .fontWeight(.medium)
                }
            }

            if let sampleRate = track.sampleRate, sampleRate > 0 {
                HStack {
                    Text("Sample Rate")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sampleRate / 1000) kHz")
                        .fontWeight(.medium)
                }
            }

            if let channels = track.channelCount, channels > 0 {
                HStack {
                    Text("Channels")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(channels == 2 ? "Stereo" : channels == 1 ? "Mono" : "\(channels) ch")
                        .fontWeight(.medium)
                }
            }
        }
        .font(.subheadline)
        .padding()
        .frame(minWidth: 200)
    }
}

// MARK: - Scrubber (Isolated)

/// Isolated view that reads `player.currentTime` and `player.duration`.
///
/// Because this is its own `struct`, observation tracking scopes the
/// per-tick invalidation to **just** this subtree.  The parent
/// `PlayerControlsView.body` is no longer re-evaluated every second,
/// which prevents context-menus from flickering.
private struct ScrubberView: View {
    @Environment(AppState.self) private var appState
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    private var player: AudioPlaybackManager { appState.audioPlayer }

    var body: some View {
        let displayTime = isSeeking ? seekTime : player.currentTime
        let totalDuration = player.duration

        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { newValue in
                        if !isSeeking { isSeeking = true }
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
                Text(TimeFormatting.playbackPosition(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-\(TimeFormatting.playbackPosition(max(totalDuration - displayTime, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Playback Controls Row (Isolated)

/// Isolated view that reads `player.isPlaying`, `queue.hasNext`, etc.
///
/// Keeps play-state changes from invalidating the parent.
private struct PlaybackControlsRow: View {
    @Environment(AppState.self) private var appState

    private var player: AudioPlaybackManager { appState.audioPlayer }
    private var queue: PlayQueue { player.queue }

    var body: some View {
        HStack(spacing: 0) {
            // Shuffle
            Button {
                queue.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(queue.shuffleEnabled ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()

            // Previous
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(queue.hasPrevious ? .primary : .tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasNext)
            
            Spacer()

            // Repeat
            Button {
                queue.cycleRepeatMode()
            } label: {
                Image(
                    systemName: queue.repeatMode == .one ? "repeat.1" : "repeat"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(queue.repeatMode != .off ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Favorite Button (Isolated)

/// Small isolated view so the favorite API call / optimistic toggle
/// doesn't cause the parent to re-render.
private struct FavoriteButton: View {
    let track: Track
    @Environment(AppState.self) private var appState

    var body: some View {
        let isFav = track.userData?.isFavorite == true

        Button {
            Task {
                do {
                    try await appState.provider.setFavorite(itemId: track.id, isFavorite: !isFav)
                    appState.showToast(
                        isFav ? "Removed from Favorites" : "Added to Favorites",
                        icon: isFav ? "heart" : "heart.fill"
                    )
                } catch {
                    // Silently fail
                }
            }
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isFav ? Color.red : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sleep Timer Button (Isolated)

/// Isolated view that reads `player.sleepTimerMode` and
/// `player.sleepTimerRemaining` so the per-second countdown
/// doesn't invalidate the parent toolbar.
private struct SleepTimerButton: View {
    @Environment(AppState.self) private var appState

    private var player: AudioPlaybackManager { appState.audioPlayer }

    var body: some View {
        Menu {
            if player.sleepTimerMode != nil {
                Button(role: .destructive) {
                    player.cancelSleepTimer()
                    appState.showToast("Sleep timer cancelled", icon: "moon.zzz")
                } label: {
                    Label("Cancel Timer", systemImage: "xmark.circle")
                }

                Divider()
            }

            Button {
                player.setSleepTimer(.minutes(5))
            } label: {
                Text("5 minutes")
            }
            Button {
                player.setSleepTimer(.minutes(10))
            } label: {
                Text("10 minutes")
            }
            Button {
                player.setSleepTimer(.minutes(15))
            } label: {
                Text("15 minutes")
            }
            Button {
                player.setSleepTimer(.minutes(30))
            } label: {
                Text("30 minutes")
            }
            Button {
                player.setSleepTimer(.minutes(45))
            } label: {
                Text("45 minutes")
            }
            Button {
                player.setSleepTimer(.minutes(60))
            } label: {
                Text("1 hour")
            }

            Divider()

            Button {
                player.setSleepTimer(.endOfTrack)
            } label: {
                Text("End of Track")
            }
        } label: {
            Group {
                if player.sleepTimerMode != nil {
                    let remaining = Int(player.sleepTimerRemaining)
                    if remaining > 0 {
                        Text("\(remaining / 60)m")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Image(systemName: "moon.zzz.fill")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Image(systemName: "moon.zzz")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
    }
}
