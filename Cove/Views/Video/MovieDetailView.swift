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

    var body: some View {
        ScrollView {
            VideoDetailScaffold(
                item: item,
                displayItem: displayItem,
                backdropURL: backdropURL,
                posterURL: posterURL,
                heroSubtitleParts: heroSubtitleParts,
                libraryId: moviesLibraryId,
                header: {
                    VStack(alignment: .leading, spacing: 8) {
                        PlayButton(item: item)
                        EndsAtLabel(item: item)
                    }
                },
                footer: {
                    VStack(alignment: .leading, spacing: 20) {
                        // Last played date
                        if let lastPlayed = item.userData?.lastPlayedDate {
                            LastPlayedLabel(date: lastPlayed)
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

                        MediaItemRail(title: "Trailers", style: .landscape) { [item] in
                            try await authManager.provider.localTrailers(for: item)
                        }

                        MediaItemRail(title: "Special Features", style: .landscape) { [item] in
                            try await authManager.provider.specialFeatures(for: item)
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
        .onChange(of: appState.videoPlayerCoordinator.isPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                Task {
                    // Allow time for the playback stop report to reach the server
                    try? await Task.sleep(for: .seconds(2))
                    await detailLoader.load {
                        try await authManager.provider.item(id: item.id)
                    }
                }
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

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    /// The ID of the first movies library, used for genre chip navigation.
    private var moviesLibraryId: ItemID? {
        appState.libraries.first { $0.collectionType == .movies }?.id
    }

    // MARK: - Hero Subtitle Parts

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        // Use premiere date if available, otherwise fall back to production year
        if let premiereDate = displayItem.premiereDate {
            parts.append(premiereDate.formatted(date: .abbreviated, time: .omitted))
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

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private var posterURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }

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

// MARK: - Last Played Label

/// A subtle label showing when the user last watched this item.
private struct LastPlayedLabel: View {
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
