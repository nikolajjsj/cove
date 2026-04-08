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

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VideoDetailScaffold(
                item: item,
                displayItem: displayItem,
                backdropURL: backdropURL,
                heroSubtitleParts: heroSubtitleParts,
                metadataPills: buildMetadataPills(),
                header: {
                    playButton
                },
                footer: {
                    VStack(alignment: .leading, spacing: 20) {
                        if !displayItem.people.isEmpty {
                            CastCrewRail(people: displayItem.people)
                        }

                        MediaItemRail(title: "Trailers") { [item] in
                            try await authManager.provider.localTrailers(for: item)
                        }

                        MediaItemRail(title: "Special Features") { [item] in
                            try await authManager.provider.specialFeatures(for: item)
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

    /// The fully-fetched item (with people & remote trailers), falling back to the navigation item.
    private var displayItem: MediaItem {
        detailLoader.displayItem(fallback: item)
    }

    // MARK: - Hero Subtitle Parts

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
