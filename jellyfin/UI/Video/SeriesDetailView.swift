import ImageService
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI
import MediaServerKit

struct SeriesDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var seasons: [Season] = []
    @State private var selectedSeason: Season?
    @State private var episodes: [Episode] = []
    @State private var isLoadingSeasons = true
    @State private var isLoadingEpisodes = false
    @State private var seasonsError: String?
    @State private var episodesError: String?

    // Playback
    @State private var showPlayer = false
    @State private var selectedEpisodeItem: MediaItem?
    @State private var streamInfo: StreamInfo?
    @State private var isLoadingStream = false
    @State private var playbackStartPosition: TimeInterval = 0

    // Overview expansion
    @State private var isOverviewExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Backdrop

                backdropSection

                // MARK: - Title & Overview

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    if let overview = item.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal)

                // MARK: - Season Picker

                if isLoadingSeasons {
                    HStack {
                        Spacer()
                        ProgressView("Loading seasons…")
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else if let error = seasonsError {
                    ContentUnavailableView(
                        "Unable to Load Seasons",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .padding(.vertical, 32)
                } else if seasons.isEmpty {
                    ContentUnavailableView(
                        "No Seasons",
                        systemImage: "tv",
                        description: Text("This series doesn't have any seasons yet.")
                    )
                    .padding(.vertical, 32)
                } else {
                    seasonPickerSection
                        .padding(.top, 16)

                    // MARK: - Episode List

                    episodeListSection
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(item.title)
        .task {
            await loadSeasons()
        }
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showPlayer) {
                if let streamInfo, let episodeItem = selectedEpisodeItem {
                    VideoPlayerView(
                        item: episodeItem,
                        streamInfo: streamInfo,
                        startPosition: playbackStartPosition
                    )
                }
            }
        #endif
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdropSection: some View {
        LazyImage(url: backdropURL(for: item)) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
            } else if state.isLoading {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .overlay { ProgressView() }
            } else {
                // Gradient placeholder when no backdrop
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .blue.opacity(0.4), .purple.opacity(0.3), .black.opacity(0.2),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .overlay {
                        Image(systemName: "tv")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .clipShape(Rectangle())
        .overlay(alignment: .bottomLeading) {
            // Poster overlay
            LazyImage(url: posterURL(for: item)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(2.0 / 3.0, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .aspectRatio(2.0 / 3.0, contentMode: .fill)
                        .overlay {
                            Image(systemName: "tv")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .padding(.leading, 16)
            .padding(.bottom, -30)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.primary.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isOverviewExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: isOverviewExpanded)

            if overview.count > 150 {
                Button {
                    isOverviewExpanded.toggle()
                } label: {
                    Text(isOverviewExpanded ? "Show Less" : "Show More")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    // MARK: - Season Picker

    @ViewBuilder
    private var seasonPickerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasons) { season in
                    Button {
                        selectSeason(season)
                    } label: {
                        Text(season.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        selectedSeason?.id == season.id
                                            ? Color.accentColor
                                            : Color(.secondarySystemFill)
                                    )
                            )
                            .foregroundStyle(
                                selectedSeason?.id == season.id ? .white : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Episode List

    @ViewBuilder
    private var episodeListSection: some View {
        if isLoadingEpisodes {
            HStack {
                Spacer()
                ProgressView("Loading episodes…")
                Spacer()
            }
            .padding(.vertical, 32)
        } else if let error = episodesError {
            ContentUnavailableView(
                "Unable to Load Episodes",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .padding(.vertical, 32)
        } else if episodes.isEmpty {
            ContentUnavailableView(
                "No Episodes",
                systemImage: "play.rectangle",
                description: Text("No episodes found for this season.")
            )
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    EpisodeRow(
                        episode: episode,
                        thumbnailURL: episodeThumbnailURL(for: episode),
                        progress: episodeProgress(for: episode),
                        onPlay: {
                            playEpisode(episode)
                        }
                    )

                    if index < episodes.count - 1 {
                        Divider()
                            .padding(.leading, 172)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data Loading

    private func loadSeasons() async {
        isLoadingSeasons = true
        seasonsError = nil
        do {
            let loadedSeasons = try await appState.provider.seasons(series: item.id)
            seasons = loadedSeasons.sorted { $0.seasonNumber < $1.seasonNumber }
            if let first = seasons.first {
                selectedSeason = first
                await loadEpisodes(for: first)
            }
        } catch {
            seasonsError = error.localizedDescription
        }
        isLoadingSeasons = false
    }

    private func loadEpisodes(for season: Season) async {
        isLoadingEpisodes = true
        episodesError = nil
        do {
            let loaded = try await appState.provider.episodes(season: season.id)
            episodes = loaded.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
        } catch {
            episodesError = error.localizedDescription
            episodes = []
        }
        isLoadingEpisodes = false
    }

    private func selectSeason(_ season: Season) {
        guard season.id != selectedSeason?.id else { return }
        selectedSeason = season
        Task {
            await loadEpisodes(for: season)
        }
    }

    // MARK: - Playback

    private func playEpisode(_ episode: Episode) {
        guard !isLoadingStream else { return }
        Task {
            isLoadingStream = true
            defer { isLoadingStream = false }
            do {
                let episodeMediaItem = try await appState.provider.item(id: episode.id)
                let info = try await appState.provider.streamURL(
                    for: episodeMediaItem, profile: nil)
                selectedEpisodeItem = episodeMediaItem
                streamInfo = info
                playbackStartPosition = episodeMediaItem.userData?.playbackPosition ?? 0
                showPlayer = true
            } catch {
                // Could show an alert here in the future
            }
        }
    }

    // MARK: - Image Helpers

    private func backdropURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private func posterURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }

    private func episodeThumbnailURL(for episode: Episode) -> URL? {
        appState.provider.imageURL(
            for: episode.id,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
    }

    // MARK: - Progress

    private func episodeProgress(for episode: Episode) -> Double? {
        guard let runtime = episode.runtime, runtime > 0 else { return nil }
        // We don't have direct userData on Episode, so we can't compute progress here
        // without fetching each episode as a MediaItem. Return nil for now —
        // the caller can enhance this later with a lookup cache.
        return nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SeriesDetailView(
            item: MediaItem(
                id: ItemID("preview-series"),
                title: "Preview Series",
                overview:
                    "A thrilling series about software engineers building a media player. Things get complicated when concurrency comes into play.",
                mediaType: .series
            )
        )
        .environment(AppState())
    }
}
