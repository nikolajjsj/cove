import CoveUI
import DownloadManager
import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct MovieDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var detailLoader = DetailItemLoader()
    @State private var isFavorite: Bool
    @State private var isPlayed: Bool

    init(item: MediaItem) {
        self.item = item
        _isFavorite = State(initialValue: item.userData?.isFavorite ?? false)
        _isPlayed = State(initialValue: item.userData?.isPlayed ?? false)
    }

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Backdrop

                heroSection

                // MARK: - Content beneath the hero

                VStack(alignment: .leading, spacing: 20) {
                    playButton

                    // Metadata pills row (ratings + media info)
                    metadataPills

                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        ExpandableOverview(text: overview)
                    }

                    // External Links (IMDb, TMDB)
                    if let providerIds = displayItem.providerIds, providerIds.hasAny {
                        ExternalLinksSection(
                            providerIds: providerIds,
                            mediaType: item.mediaType
                        )
                    }

                    // Genres
                    if let genres = item.genres, !genres.isEmpty {
                        GenreTagsSection(genres: genres)
                    }

                    // Studios
                    if let studios = displayItem.studios, !studios.isEmpty {
                        StudiosSection(studios: studios)
                    }

                    // Cast & Crew
                    if !displayItem.people.isEmpty {
                        CastCrewRail(people: displayItem.people)
                    }

                    // Trailers
                    MediaItemRail(title: "Trailers") { [item] in
                        try await authManager.provider.localTrailers(for: item)
                    }

                    // Special Features
                    MediaItemRail(title: "Special Features") { [item] in
                        try await authManager.provider.specialFeatures(for: item)
                    }

                    // More Like This
                    MediaItemRail(title: "More Like This") { [item] in
                        try await authManager.provider.similarItems(for: item, limit: 12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .task {
            await detailLoader.load {
                try await authManager.provider.item(id: item.id)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(item.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
                    Button {
                        let wasFavorite = isFavorite
                        isFavorite.toggle()
                        Task {
                            await appState.toggleFavorite(itemId: item.id, isFavorite: wasFavorite)
                        }
                    } label: {
                        Label(
                            isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }

                    Button {
                        let wasPlayed = isPlayed
                        isPlayed.toggle()
                        Task { await appState.togglePlayed(itemId: item.id, isPlayed: wasPlayed) }
                    } label: {
                        Label(
                            isPlayed ? "Mark as Unwatched" : "Mark as Watched",
                            systemImage: isPlayed ? "eye.slash" : "eye"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
    }

    /// The fully-fetched item (with people & remote trailers), falling back to the navigation item.
    private var displayItem: MediaItem {
        detailLoader.displayItem(fallback: item)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HeroSection(imageURL: backdropURL) {
            VideoHeroOverlay(
                title: item.title,
                originalTitle: displayItem.originalTitle,
                subtitleParts: heroSubtitleParts,
                tagline: displayItem.tagline
            )
        }
    }

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        // Use premiere date if available, otherwise fall back to production year
        if let premiereDate = displayItem.premiereDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            parts.append(formatter.string(from: premiereDate))
        } else if let year = item.productionYear {
            parts.append(String(year))
        }

        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }

        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        return parts
    }

    // MARK: - Metadata Pills

    @ViewBuilder
    private var metadataPills: some View {
        MetadataPillsView(buildMetadataPills())
    }

    private func buildMetadataPills() -> [MetadataPill] {
        var pills = MetadataPill.ratingPills(
            communityRating: item.communityRating,
            criticRating: item.criticRating,
            hasImdb: displayItem.providerIds?.imdb != nil
        )

        // Media info pills from streams
        if let streams = displayItem.mediaStreams {
            // Resolution pill from the first video stream
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

            // Audio channels pill from the first audio stream
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

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            coordinator.play(item: item, using: authManager.provider)
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

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }
}
