import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// Detail view for a smart playlist preset.
///
/// Displays a gradient header with the preset's icon and metadata,
/// play/shuffle action buttons, and a scrollable track list.
/// Results are fetched from the Jellyfin server using the preset's
/// filter + sort configuration and cached with a high TTL so the
/// list remains stable across repeated visits.
struct SmartPlaylistDetailView: View {
    let preset: SmartPlaylist
    let library: MediaLibrary?

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Resolves the music library — uses the explicitly provided one, or falls back
    /// to the first music library found in AppState.
    private var resolvedLibrary: MediaLibrary? {
        library ?? appState.libraries.first { $0.collectionType == .music }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading tracks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Tracks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("No tracks match this smart playlist's criteria.")
                )
            } else {
                scrollContent
            }
        }
        .navigationTitle(preset.name)
        .inlineNavigationTitle()
        .task { await loadTracks() }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                presetHeader
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

    // MARK: - Header

    private var presetHeader: some View {
        VStack(spacing: 16) {
            SmartPlaylistHeaderIcon(preset: preset)
                .frame(width: 160, height: 160)
                .shadow(
                    color: preset.gradientColors.first?.opacity(0.4) ?? .clear, radius: 16, y: 8)

            VStack(spacing: 6) {
                Text(preset.name)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(preset.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                trackCountLabel
            }
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    private var trackCountLabel: some View {
        HStack(spacing: 6) {
            Text("\(items.count) \(items.count == 1 ? "track" : "tracks")")

            if let totalDuration {
                Text("·")
                Text(TimeFormatting.longDuration(totalDuration))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var totalDuration: TimeInterval? {
        let sum = items.compactMap(\.runtime).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        PlayShuffleButtons(
            isDisabled: items.isEmpty,
            onPlay: { playAllTracks(startingAt: 0) },
            onShuffle: { playShuffled() }
        )
    }

    // MARK: - Track List

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(items.enumerated(), id: \.element.id) { index, item in
                TrackRow(
                    title: item.title,
                    subtitle: item.artistName ?? item.albumName,
                    imageURL: trackImageURL(for: item),
                    duration: item.runtime,
                    isCurrentTrack: isCurrentTrack(item),
                    isPlaying: isCurrentTrack(item) && appState.audioPlayer.isPlaying,
                    onTap: { playAllTracks(startingAt: index) }
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
                .mediaContextMenu(item: item)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Playback

    private func playAllTracks(startingAt index: Int) {
        let tracks = items.map { item in
            Track(
                id: TrackID(item.id.rawValue),
                title: item.title,
                albumId: item.albumId.map { AlbumID($0.rawValue) },
                albumName: item.albumName,
                artistName: item.artistName,
                duration: item.runtime,
                userData: item.userData
            )
        }
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func playShuffled() {
        let tracks = items.map { item in
            Track(
                id: TrackID(item.id.rawValue),
                title: item.title,
                albumId: item.albumId.map { AlbumID($0.rawValue) },
                albumName: item.albumName,
                artistName: item.artistName,
                duration: item.runtime,
                userData: item.userData
            )
        }
        guard !tracks.isEmpty else { return }
        var shuffled = tracks
        shuffled.shuffle()
        appState.audioPlayer.play(tracks: shuffled, startingAt: 0)
    }

    private func isCurrentTrack(_ item: MediaItem) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id.rawValue == item.id.rawValue
    }

    // MARK: - Data Loading

    private func loadTracks() async {
        guard let library = resolvedLibrary else {
            errorMessage = "No music library available."
            isLoading = false
            return
        }

        let provider = authManager.provider
        let sort = SortOptions(field: preset.sortField, order: preset.sortOrder)
        let filter = FilterOptions(
            isFavorite: preset.isFavorite,
            isPlayed: preset.isPlayed,
            limit: preset.limit,
            includeItemTypes: ["Audio"]
        )

        do {
            let result = try await provider.pagedItems(
                in: library,
                sort: sort,
                filter: filter,
                cacheMaxAge: preset.cacheMaxAge
            )
            items = result.items
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Image Helpers

    private func trackImageURL(for item: MediaItem) -> URL? {
        if let albumId = item.albumId {
            return authManager.provider.imageURL(
                for: albumId, type: .primary, maxSize: CGSize(width: 80, height: 80)
            )
        }
        return authManager.provider.imageURL(
            for: item, type: .primary, maxSize: CGSize(width: 80, height: 80)
        )
    }
}

// MARK: - Header Icon

/// A large, rounded gradient icon used as the smart playlist's "artwork"
/// in the detail view header.
private struct SmartPlaylistHeaderIcon: View {
    let preset: SmartPlaylist

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: preset.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ghosted decorative icon
            Image(systemName: preset.icon)
                .font(.system(size: 100, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .rotationEffect(.degrees(-12))
                .offset(x: 24, y: 20)

            // Glass sheen
            LinearGradient(
                colors: [.white.opacity(0.22), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            // Centered icon
            Image(systemName: preset.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    let state = AppState.preview
    NavigationStack {
        SmartPlaylistDetailView(
            preset: SmartPlaylist.presets[0],
            library: nil
        )
        .environment(state)
        .environment(state.authManager)
    }
}
