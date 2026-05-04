import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import NukeUI
import PlaybackEngine
import SwiftUI

struct ArtistDetailView: View {
    let artistItem: MediaItem
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<Album>()

    @Default(.gridDensity) private var gridDensity

    var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView("Loading artist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "Unable to Load Artist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .empty, .loaded:
                ScrollView {
                    VStack(spacing: 24) {
                        ArtistHeaderView(artistItem: artistItem, imageURL: artistImageURL)
                        ArtistTopTracksSection(artistItem: artistItem)
                        ArtistAlbumsSection(albums: loader.items)
                        ContentRail(
                            title: "Similar Artists",
                            skeleton: { SkeletonCard(width: 120, isCircular: true) }
                        ) {
                            try await authManager.provider.similarItems(for: artistItem, limit: nil)
                        } card: { item in
                            ArtistCard(
                                item: item,
                                imageURL: authManager.provider.imageURL(
                                    for: item, type: .primary,
                                    maxSize: CGSize(width: 240, height: 240))
                            )
                            .frame(width: 120)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(artistItem.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavoriteToggle(itemId: artistItem.id, userData: artistItem.userData)
            }
        }
        .task {
            await loader.load {
                try await authManager.provider.albums(artist: artistItem.id)
            }
        }
    }

    // MARK: - Image Helpers

    private var artistImageURL: URL? {
        authManager.provider.imageURL(
            for: artistItem,
            type: .primary,
            maxSize: CGSize(width: 400, height: 400)
        )
    }
}

// MARK: - Artist Header View

private struct ArtistHeaderView: View {
    let artistItem: MediaItem
    let imageURL: URL?
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            // Artist image (circular)
            MediaImage(
                url: imageURL,
                placeholderIcon: "music.mic",
                placeholderIconFont: .system(size: 48),
                cornerRadius: .infinity
            )
            .frame(width: 200, height: 200)

            // Artist name
            Text(artistItem.title)
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)

            // Overview
            if let overview = artistItem.overview, !overview.isEmpty {
                ExpandableOverview(text: overview, font: .subheadline)
                    .padding(.horizontal)
            }

            Button {
                Task { await appState.startRadio(for: artistItem.id) }
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }
}

// MARK: - Artist Top Tracks Section

private struct ArtistTopTracksSection: View {
    let artistItem: MediaItem
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                // Skeleton placeholders while loading
                VStack(alignment: .leading, spacing: 0) {
                    Text("Top Tracks")
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 140, height: 14)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 90, height: 11)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                }
            } else if !tracks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Top Tracks")
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                    ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                        let isCurrentTrack = appState.audioPlayer.queue.currentTrack?.id == track.id
                        let isPlaying = appState.audioPlayer.isPlaying

                        TrackRow(
                            title: track.title,
                            subtitle: track.albumName,
                            imageURL: imageURL(for: track),
                            duration: track.duration,
                            isCurrentTrack: isCurrentTrack,
                            isPlaying: isCurrentTrack && isPlaying,
                            isFavorite: appState.userDataStore?.isFavorite(
                                track.id, fallback: track.userData
                            ) ?? track.userData?.isFavorite ?? false,
                            onTap: { playFrom(index: index) }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task(id: artistItem.id) {
            await loadTopTracks()
        }
    }

    private func loadTopTracks() async {
        isLoading = true
        do {
            tracks = try await authManager.provider.topTracks(artist: artistItem.id, limit: 5)
        } catch {
            tracks = []
        }
        isLoading = false
    }

    private func playFrom(index: Int) {
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func imageURL(for track: Track) -> URL? {
        let itemId = track.albumId ?? track.id
        return authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 88, height: 88))
    }
}

// MARK: - Artist Albums Section

private struct ArtistAlbumsSection: View {
    let albums: [Album]
    @Environment(AuthManager.self) private var authManager
    @Default(.gridDensity) private var gridDensity

    var body: some View {
        if albums.isEmpty {
            ContentUnavailableView(
                "No Albums",
                systemImage: "square.stack",
                description: Text("No albums found for this artist.")
            )
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Albums")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(albums) { album in
                        AlbumCard(
                            album: album,
                            subtitle: [album.year.map { String($0) }, album.genre]
                                .compactMap { $0 }
                                .joined(separator: " · "),
                            imageURL: albumImageURL(for: album.id)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func albumImageURL(for itemId: ItemID) -> URL? {
        authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 300, height: 300))
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        ArtistDetailView(
            artistItem: MediaItem(
                id: ItemID("preview-artist"),
                title: "Preview Artist",
                overview: "A talented musician with many albums.",
                mediaType: .artist
            )
        )
        .environment(state)
        .environment(state.authManager)
    }
}
