import CoveUI
import DownloadManager
import ImageService
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI
import MediaServerKit

struct MovieDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isOverviewExpanded = false
    @State private var detailLoader = DetailItemLoader()

    private let overviewLineLimit = 4

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

                    // Metadata pills row
                    metadataPills

                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }

                    // Genres
                    if let genres = item.genres, !genres.isEmpty {
                        genresTags(genres)
                    }

                    // Cast & Crew
                    if !displayItem.people.isEmpty {
                        CastCrewRail(people: displayItem.people)
                    }

                    // Trailers
                    MediaItemRail(title: "Trailers") { [item] in
                        try await appState.provider.localTrailers(for: item)
                    }

                    // Special Features
                    MediaItemRail(title: "Special Features") { [item] in
                        try await appState.provider.specialFeatures(for: item)
                    }

                    // More Like This
                    MediaItemRail(title: "More Like This") { [item] in
                        try await appState.provider.similarItems(for: item, limit: 12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .task {
            await detailLoader.load {
                try await appState.provider.item(id: item.id)
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
                if let downloadManager = appState.downloadManager {
                    let appState = appState
                    DownloadButton(
                        item: item,
                        serverId: appState.activeConnection?.id.uuidString ?? "",
                        downloadManager: downloadManager,
                        downloadURLResolver: {
                            let info = try await appState.provider.downloadInfo(
                                for: item, profile: appState.provider.deviceProfile())
                            return info.url
                        },
                        onDownload: {
                            try await appState.downloadItem(item)
                        }
                    )
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
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                heroSubtitleLine
            }
        }
    }

    // MARK: - Hero Subtitle (year · rating · runtime)

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
        var pills: [MetadataPill] = []

        if let pill = MetadataPill.communityRating(item.communityRating ?? 0) {
            pills.append(pill)
        }

        if let pill = MetadataPill.criticRating(item.criticRating ?? 0) {
            pills.append(pill)
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
            coordinator.play(item: item, using: appState.provider)
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

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(overview)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(isOverviewExpanded ? nil : overviewLineLimit)
                .animation(.easeInOut(duration: 0.25), value: isOverviewExpanded)

            Button {
                isOverviewExpanded.toggle()
            } label: {
                Text(isOverviewExpanded ? "Show Less" : "Show More")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: - Genre Tags

    @ViewBuilder
    private func genresTags(_ genres: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Genres")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
            }
        }
    }

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }
}
