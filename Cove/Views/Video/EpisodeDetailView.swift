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
                metadataPills: buildMetadataPills(),
                header: {
                    EpisodePlayButton(
                        item: item,
                        coordinator: coordinator,
                        provider: authManager.provider
                    )
                },
                footer: {
                    VStack(alignment: .leading, spacing: 20) {
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
                        }

                        MediaItemRail(title: "More Like This") { [item] in
                            try await authManager.provider.similarItems(for: item, limit: 12)
                        }
                    }
                    .padding(.horizontal)
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

        return parts
    }

    // MARK: - Metadata Pills

    private func buildMetadataPills() -> [MetadataPill] {
        var pills = MetadataPill.ratingPills(
            communityRating: item.communityRating,
            criticRating: item.criticRating,
            hasImdb: displayItem.providerIds?.imdb != nil
        )

        if let streams = displayItem.mediaStreams {
            if let videoStream = streams.first(where: { $0.type == .video }) {
                if let pill = MetadataPill.resolution(width: videoStream.width ?? 0) {
                    pills.append(pill)
                }
                if let pill = MetadataPill.hdr(
                    videoRange: videoStream.videoRange,
                    videoRangeType: videoStream.videoRangeType
                ) {
                    pills.append(pill)
                }
            }

            if let audioStream = streams.first(where: { $0.type == .audio }) {
                if let pill = MetadataPill.audioChannels(audioStream.channels ?? 0) {
                    pills.append(pill)
                }
            }
        }

        if let userData = item.userData {
            if userData.isPlayed {
                pills.append(.played)
            }
            if let pill = MetadataPill.playCount(userData.playCount) {
                pills.append(pill)
            }
        }

        return pills
    }
}

// MARK: - Episode Play Button

private struct EpisodePlayButton: View {
    let item: MediaItem
    let coordinator: VideoPlayerCoordinator
    let provider: JellyfinServerProvider

    var body: some View {
        Button {
            coordinator.play(item: item, using: provider)
        } label: {
            HStack(spacing: 8) {
                if coordinator.isLoadingItem(item.id) {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body)
                }
                Text(playButtonLabel)
                    .fontWeight(.semibold)
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(coordinator.isLoadingItem(item.id))
    }

    private var playButtonLabel: String {
        if let position = item.userData?.playbackPosition, position > 0 {
            return "Resume at \(TimeFormatting.playbackPosition(position))"
        }
        return "Play"
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
