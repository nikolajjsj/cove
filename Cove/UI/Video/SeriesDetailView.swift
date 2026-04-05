import CoveUI
import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

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

    // Overview expansion
    @State private var isOverviewExpanded = false

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Backdrop

                heroSection

                // MARK: - Content beneath the hero

                VStack(alignment: .leading, spacing: 16) {
                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }

                    // Metadata pills
                    metadataPills
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal)

                // MARK: - Season Picker & Episodes

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

                    episodeListSection
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(item.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadSeasons()
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HeroSection(imageURL: backdropURL(for: item)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                heroSubtitleLine
            }
        }
    }

    // MARK: - Hero Subtitle (year · rating · seasons count)

    @ViewBuilder
    private var heroSubtitleLine: some View {
        let parts = heroSubtitleParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Text(part)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        if let year = item.productionYear {
            parts.append(String(year))
        }

        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }

        if !seasons.isEmpty {
            let count = seasons.count
            parts.append("\(count) Season\(count == 1 ? "" : "s")")
        }

        return parts
    }

    // MARK: - Metadata Pills

    @ViewBuilder
    private var metadataPills: some View {
        MetadataPillsView(buildMetadataPills())
    }

    private func buildMetadataPills() -> [MetadataPill] {
        var pills: [MetadataPill] = []

        if let pill = MetadataPill.communityRating(item.communityRating ?? 0) {
            pills.append(pill)
        }

        if let pill = MetadataPill.criticRating(item.criticRating ?? 0) {
            pills.append(pill)
        }

        if let genres = item.genres, let first = genres.first {
            pills.append(.genre(first))
        }

        return pills
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
            LazyVStack(spacing: 5) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    EpisodeRow(
                        episode: episode,
                        thumbnailURL: episodeThumbnailURL(for: episode),
                        progress: episodeProgress(for: episode),
                        onPlay: {
                            coordinator.playEpisode(
                                id: episode.id,
                                title: episode.title,
                                using: appState.provider
                            )
                        }
                    )
                    .overlay {
                        if coordinator.isLoadingItem(episode.id) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .overlay { ProgressView() }
                        }
                    }

                    if index < episodes.count - 1 {
                        Divider()
                            .padding(.leading, 172)
                            .padding(.top, 4)
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

    // MARK: - Image Helpers

    private func backdropURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
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
