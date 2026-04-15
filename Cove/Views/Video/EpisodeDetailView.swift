import CoveUI
import DownloadManager
import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct EpisodeDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator

    @State private var detailLoader = DetailItemLoader()

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VideoDetailScaffold(
                item: item,
                displayItem: displayItem,
                backdropURL: heroImageURL,
                heroSubtitleParts: heroSubtitleParts,
                metadataPills: MetadataPill.videoDetailPills(for: item, displayItem: displayItem),
                libraryId: tvShowsLibraryId,
                header: {
                    PlayButton(item: item)
                },
                footer: {
                    VStack(alignment: .leading, spacing: 20) {
                        // Last played date
                        if let lastPlayed = item.userData?.lastPlayedDate {
                            EpisodeLastPlayedLabel(date: lastPlayed)
                                .padding(.horizontal)
                        }

                        // Chapter markers
                        if !displayItem.chapters.isEmpty {
                            ChapterRail(
                                chapters: displayItem.chapters,
                                chapterImageURL: { chapter in
                                    chapterImageURL(for: chapter)
                                },
                                onSelect: { chapter in
                                    coordinator.play(
                                        item: item,
                                        using: authManager.provider,
                                        startingAt: chapter.startPosition
                                    )
                                }
                            )
                        }

                        if !displayItem.people.isEmpty {
                            CastCrewRail(people: displayItem.people)
                        }

                        if let seriesId = item.seriesId {
                            MoreEpisodesSection(
                                item: item,
                                seriesId: seriesId,
                                coordinator: coordinator,
                                provider: authManager.provider
                            )
                            .padding(.horizontal)
                        }

                        MediaItemRail(title: "More Like This") { [item] in
                            try await authManager.provider.similarItems(for: item, limit: 12)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            )
        }
        .task {
            await detailLoader.load {
                try await authManager.provider.item(id: item.id)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let downloadManager = downloadCoordinator.downloadManager {
                    DownloadButton(
                        item: item,
                        serverId: authManager.activeConnection?.id.uuidString ?? "",
                        downloadManager: downloadManager,
                        downloadURLResolver: {
                            let info = try await authManager.provider.downloadInfo(
                                for: item, profile: authManager.provider.deviceProfile())
                            return info.url
                        },
                        onDownload: {
                            try await downloadCoordinator.downloadItem(item)
                        }
                    )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    FavoriteToggle(itemId: item.id, userData: item.userData)
                    PlayedToggle(itemId: item.id, userData: item.userData)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
    }

    // MARK: - Display Item

    private var displayItem: MediaItem {
        detailLoader.displayItem(fallback: item)
    }

    /// The ID of the first TV shows library, used for genre chip navigation.
    private var tvShowsLibraryId: ItemID? {
        appState.libraries.first { $0.collectionType == .tvshows }?.id
    }

    // MARK: - Hero Image

    private var heroImageURL: URL? {
        // Prefer the episode's own primary image (screenshot)
        let episodeImage = authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 1280, height: 720)
        )
        if episodeImage != nil {
            return episodeImage
        }
        // Fall back to the series backdrop
        if let seriesId = item.seriesId {
            return authManager.provider.imageURL(
                for: seriesId,
                type: .backdrop,
                maxSize: CGSize(width: 1280, height: 720)
            )
        }
        return nil
    }

    // MARK: - Hero Subtitle

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        if let seriesName = item.seriesName, !seriesName.isEmpty {
            parts.append(seriesName)
        }

        let seasonNumber = item.parentIndexNumber
        let episodeNumber = item.indexNumber
        if let s = seasonNumber, let e = episodeNumber {
            parts.append("S\(s) E\(e)")
        } else if let e = episodeNumber {
            parts.append("E\(e)")
        }

        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        // Air date for episodes
        if let premiereDate = displayItem.premiereDate {
            parts.append(premiereDate.formatted(date: .abbreviated, time: .omitted))
        }

        return parts
    }

    // MARK: - Chapter Image

    private func chapterImageURL(for chapter: Chapter) -> URL? {
        guard let tag = chapter.imageTag else { return nil }
        return authManager.provider.chapterImageURL(
            itemId: item.id,
            chapterIndex: chapter.id,
            tag: tag,
            maxWidth: 400
        )
    }
}

// MARK: - Episode Last Played Label

/// A subtle label showing when the user last watched this episode.
private struct EpisodeLastPlayedLabel: View {
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Text("Last watched \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - More Episodes Section

private struct MoreEpisodesSection: View {
    let item: MediaItem
    let seriesId: ItemID
    let coordinator: VideoPlayerCoordinator
    let provider: JellyfinServerProvider

    @State private var nearbyEpisodes: [Episode] = []
    @State private var isLoading = true

    var body: some View {
        if isLoading {
            VStack {
                ProgressView()
                    .padding(.vertical)
            }
            .task {
                await loadNearbyEpisodes()
            }
        } else if !nearbyEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle

                LazyVStack(spacing: 5) {
                    ForEach(nearbyEpisodes.enumerated(), id: \.element.id) { index, episode in
                        EpisodeRow(
                            episode: episode,
                            thumbnailURL: episodeThumbnailURL(for: episode),
                            progress: episodeProgress(for: episode),
                            onPlay: {
                                coordinator.playEpisode(
                                    id: episode.id,
                                    title: episode.title,
                                    using: provider
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

                        if index < nearbyEpisodes.count - 1 {
                            Divider()
                                .padding(.leading, 172)
                                .padding(.top, 4)
                        }
                    }
                }

                seeAllLink
            }
        }
    }

    // MARK: - Section Title

    private var sectionTitle: some View {
        Group {
            if let seasonNumber = item.parentIndexNumber {
                Text("More from Season \(seasonNumber)")
                    .font(.title3.bold())
            } else {
                Text("More Episodes")
                    .font(.title3.bold())
            }
        }
    }

    // MARK: - See All Link

    private var seeAllLink: some View {
        NavigationLink(
            value: MediaItem(
                id: seriesId,
                title: item.seriesName ?? "Series",
                mediaType: .series
            )
        ) {
            HStack {
                Text("See All Episodes")
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.accent)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data Loading

    private func loadNearbyEpisodes() async {
        defer { isLoading = false }

        guard let currentEpisodeNumber = item.indexNumber else { return }

        do {
            let seasons = try await provider.seasons(series: seriesId)
            let matchingSeason = seasons.first { $0.seasonNumber == item.parentIndexNumber }

            guard let season = matchingSeason else { return }

            let allEpisodes = try await provider.episodes(season: season.id)
            let sorted = allEpisodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }

            // Filter to 2 episodes before and 2 after the current one, excluding the current
            let filtered = sorted.filter { episode in
                guard let epNum = episode.episodeNumber else { return false }
                guard epNum != currentEpisodeNumber else { return false }
                return epNum >= currentEpisodeNumber - 2 && epNum <= currentEpisodeNumber + 2
            }

            nearbyEpisodes = filtered
        } catch {
            // Silently fail — section simply won't appear
        }
    }

    // MARK: - Helpers

    private func episodeThumbnailURL(for episode: Episode) -> URL? {
        provider.imageURL(
            for: episode.id,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
    }

    private func episodeProgress(for episode: Episode) -> Double? {
        guard let runtime = episode.runtime, runtime > 0,
            let userData = episode.userData,
            userData.playbackPosition > 0
        else { return nil }
        return min(userData.playbackPosition / runtime, 1.0)
    }
}
