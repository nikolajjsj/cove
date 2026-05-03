import CoveUI
import DownloadManager
import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import Persistence
import PlaybackEngine
import SwiftUI

struct SeriesDetailView: View {
    let item: MediaItem
    /// When non-nil, the view operates in offline mode using local storage.
    private let offlineServerId: String?

    init(item: MediaItem) {
        self.item = item
        self.offlineServerId = nil
    }

    init(offlineSeriesId: String, serverId: String, title: String) {
        self.item = MediaItem(id: ItemID(offlineSeriesId), title: title, mediaType: .series)
        self.offlineServerId = serverId
    }

    private var isOffline: Bool { offlineServerId != nil }

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var seasons: [Season] = []
    @State private var selectedSeason: Season?
    @State private var episodes: [Episode] = []
    @State private var isLoadingSeasons = true
    @State private var isLoadingEpisodes = false
    @State private var seasonsError: String?
    @State private var episodesError: String?

    // Mark series watched/unwatched
    @State private var isMarkingSeriesWatched = false
    @State private var showMarkSeriesWatchedConfirmation = false
    @State private var markSeriesWatchedValue = true

    // Download sheet
    @State private var showDownloadSheet = false
    @State private var downloadingSeasons: Set<SeasonID> = []
    @State private var downloadedSeasons: Set<SeasonID> = []
    @State private var downloadError: String?
    @State private var showDownloadError = false

    // Offline state
    @State private var offlineSeriesMetadata: OfflineMediaMetadata?
    @State private var offlineEpisodeMetadata: [String: OfflineMediaMetadata] = [:]
    @State private var offlineEpisodeDownloads: [DownloadItem] = []
    @State private var showDeleteSeriesConfirmation = false
    @State private var episodeToDelete: DownloadItem?
    @State private var detailLoader = DetailItemLoader()

    /// The fully-fetched item (with people data), falling back to the navigation item.
    private var displayItem: MediaItem {
        detailLoader.displayItem(fallback: item)
    }

    /// The ID of the first TV shows library, used for genre chip navigation.
    private var tvShowsLibraryId: ItemID? {
        appState.libraries.first { $0.collectionType == .tvshows }?.id
    }

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VideoDetailScaffold(
                item: item,
                displayItem: displayItem,
                backdropURL: backdropURL(for: item),
                posterURL: posterURL,
                heroSubtitleParts: heroSubtitleParts,

                showExternalLinks: !isOffline,
                overviewLineLimit: 3,
                overviewFont: .subheadline,
                libraryId: tvShowsLibraryId,
                header: {
                    EmptyView()
                },
                footer: {
                    VStack(alignment: .leading, spacing: 0) {
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
                            SeasonPickerSection(
                                seasons: seasons,
                                selectedSeason: selectedSeason,
                                onSelectSeason: selectSeason
                            )
                            .padding(.top, 16)

                            EpisodeListSection(
                                isLoadingEpisodes: isLoadingEpisodes,
                                episodesError: episodesError,
                                episodes: episodes,
                                isOffline: isOffline,
                                isFirstSeason: seasons.first?.id == selectedSeason?.id,
                                offlineEpisodeDownloads: offlineEpisodeDownloads,
                                seriesId: item.id,
                                seriesName: item.title,
                                thumbnailURL: { episodeThumbnailURL(for: $0) },
                                progress: { episodeProgress(for: $0) },
                                onPlay: { episode in
                                    if let serverId = offlineServerId {
                                        playOfflineEpisode(episode, serverId: serverId)
                                    } else {
                                        coordinator.playEpisode(
                                            id: episode.id,
                                            title: episode.title,
                                            using: authManager.provider
                                        )
                                    }
                                },
                                onRequestDelete: { dl in episodeToDelete = dl },
                                onMarkPreviousWatched: { episode in
                                    Task { await markEpisodesBeforePlayed(episode) }
                                }
                            )
                            .padding(.top, 8)
                        }

                        // MARK: - Additional Content

                        if !isOffline {
                            VStack(alignment: .leading, spacing: 20) {
                                if !displayItem.people.isEmpty {
                                    CastCrewRail(people: displayItem.people)
                                }

                                MediaItemRail(title: "Special Features", style: .landscape) {
                                    [item] in
                                    try await authManager.provider.specialFeatures(for: item)
                                }

                                MediaItemRail(title: "More Like This") { [item] in
                                    try await authManager.provider.similarItems(
                                        for: item, limit: 12)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                    .padding(.bottom, 32)
                }
            )
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !isOffline {
                ToolbarItem(placement: .topBarTrailing) {
                    if downloadCoordinator.downloadManager != nil && !seasons.isEmpty {
                        Button {
                            showDownloadSheet = true
                        } label: {
                            Label("Download Season", systemImage: "arrow.down.circle")
                                .font(.title3)
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !isOffline {
                        FavoriteToggle(itemId: item.id, userData: item.userData)

                        Button {
                            markSeriesWatchedValue = true
                            showMarkSeriesWatchedConfirmation = true
                        } label: {
                            Label("Mark Series as Watched", systemImage: "eye.circle")
                        }

                        Button {
                            markSeriesWatchedValue = false
                            showMarkSeriesWatchedConfirmation = true
                        } label: {
                            Label("Mark Series as Unwatched", systemImage: "eye.slash.circle")
                        }
                    }

                    if isOffline {
                        Button(role: .destructive) {
                            showDeleteSeriesConfirmation = true
                        } label: {
                            Label("Remove All Episodes", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showDownloadSheet) {
            SeasonDownloadSheet(
                seasons: seasons,
                item: item,
                downloadingSeasons: downloadingSeasons,
                downloadedSeasons: downloadedSeasons,
                onDownloadSeason: { season in await downloadSeason(season) },
                onDownloadAll: { await downloadAllSeasons() },
                onDismiss: { showDownloadSheet = false }
            )
        }
        .alert("Download Error", isPresented: $showDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let downloadError {
                Text(downloadError)
            }
        }
        .confirmationDialog(
            markSeriesWatchedValue ? "Mark Series as Watched?" : "Mark Series as Unwatched?",
            isPresented: $showMarkSeriesWatchedConfirmation,
            titleVisibility: .visible
        ) {
            Button(markSeriesWatchedValue ? "Mark as Watched" : "Mark as Unwatched") {
                Task { await markAllEpisodesPlayed(markSeriesWatchedValue) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                markSeriesWatchedValue
                    ? "All episodes in \(item.title) will be marked as watched."
                    : "All episodes in \(item.title) will be marked as unwatched.")
        }
        .confirmationDialog(
            "Remove \(item.title)?",
            isPresented: $showDeleteSeriesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All Episodes", role: .destructive) {
                Task { await deleteAllOfflineEpisodes() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(offlineEpisodeDownloads.count) episodes will be removed from your device.")
        }
        .alert("Remove Episode?", isPresented: showDeleteEpisodeBinding) {
            Button("Cancel", role: .cancel) { episodeToDelete = nil }
            Button("Remove", role: .destructive) {
                if let ep = episodeToDelete {
                    Task { await deleteOfflineEpisode(ep) }
                    episodeToDelete = nil
                }
            }
        } message: {
            if let ep = episodeToDelete {
                Text("'\(ep.title)' will be removed from your device.")
            }
        }
        .task {
            await loadSeasons()
            if !isOffline {
                await detailLoader.load {
                    try await authManager.provider.item(id: item.id)
                }
            }
        }
        .onChange(of: appState.videoPlayerCoordinator.isPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented && !isOffline {
                Task {
                    // Allow time for the playback stop report to reach the server
                    try? await Task.sleep(for: .seconds(2))
                    await detailLoader.load {
                        try await authManager.provider.item(id: item.id)
                    }
                    if let selectedSeason {
                        await loadEpisodes(for: selectedSeason)
                    }
                }
            }
        }
    }

    // MARK: - Hero Subtitle Parts

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        // Year range for series: "2019 – 2023" or "2019 – Present"
        if let startYear = item.productionYear {
            if let endDate = displayItem.endDate {
                let calendar = Calendar.current
                let endYear = calendar.component(.year, from: endDate)
                if endYear != startYear {
                    parts.append("\(startYear) – \(endYear)")
                } else {
                    parts.append(String(startYear))
                }
            } else {
                // No end date — series is still running
                parts.append("\(startYear) – Present")
            }
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

    // MARK: - Data Loading

    private func loadSeasons() async {
        isLoadingSeasons = true
        seasonsError = nil

        if let serverId = offlineServerId {
            await loadOfflineSeasons(serverId: serverId)
        } else {
            do {
                let loadedSeasons = try await authManager.provider.seasons(series: item.id)
                seasons = loadedSeasons.sorted { $0.seasonNumber < $1.seasonNumber }
                if let first = seasons.first {
                    selectedSeason = first
                    await loadEpisodes(for: first)
                }
            } catch {
                seasonsError = error.localizedDescription
            }
        }
        isLoadingSeasons = false
    }

    private func loadOfflineSeasons(serverId: String) async {
        guard let metadataRepo = downloadCoordinator.offlineMetadataRepository,
            let dm = downloadCoordinator.downloadManager
        else { return }

        // Load series metadata
        offlineSeriesMetadata = try? await metadataRepo.fetch(
            itemId: item.id.rawValue, serverId: serverId
        )

        // Load all episode metadata for this series
        let allMeta = (try? await metadataRepo.fetchAll(serverId: serverId)) ?? []
        var epMetaMap: [String: OfflineMediaMetadata] = [:]
        for m in allMeta
        where m.mediaType == MediaType.episode.rawValue
            && (m.seriesId == item.id.rawValue)
        {
            epMetaMap[m.itemId] = m
        }
        offlineEpisodeMetadata = epMetaMap

        // Load completed episode downloads
        let allDownloads = (try? await dm.downloads(for: serverId)) ?? []
        offlineEpisodeDownloads = allDownloads.filter { dl in
            dl.mediaType == .episode
                && dl.state == .completed
                && (dl.parentId?.rawValue == item.id.rawValue
                    || epMetaMap[dl.itemId.rawValue]?.seriesId == item.id.rawValue)
        }

        // Derive Season objects from the episode metadata
        let seasonNumbers = Set(
            offlineEpisodeDownloads.compactMap { dl in
                epMetaMap[dl.itemId.rawValue]?.seasonNumber
            })
        seasons = seasonNumbers.sorted().map { num in
            Season(
                id: SeasonID("offline-season-\(num)"),
                seriesId: item.id,
                seasonNumber: num,
                title: num == 0 ? "Specials" : "Season \(num)"
            )
        }

        if let first = seasons.first {
            selectedSeason = first
            loadOfflineEpisodes(for: first)
        }
    }

    private func loadEpisodes(for season: Season) async {
        isLoadingEpisodes = true
        episodesError = nil

        if offlineServerId != nil {
            loadOfflineEpisodes(for: season)
        } else {
            do {
                let loaded = try await authManager.provider.episodes(season: season.id)
                episodes = loaded.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
            } catch {
                episodesError = error.localizedDescription
                episodes = []
            }
        }
        isLoadingEpisodes = false
    }

    private func loadOfflineEpisodes(for season: Season) {
        let seasonEps = offlineEpisodeDownloads.filter { dl in
            offlineEpisodeMetadata[dl.itemId.rawValue]?.seasonNumber == season.seasonNumber
        }
        episodes = seasonEps.compactMap { dl -> Episode? in
            guard let meta = offlineEpisodeMetadata[dl.itemId.rawValue] else { return nil }
            return Episode(
                id: EpisodeID(meta.itemId),
                seriesId: meta.seriesId.map { SeriesID($0) },
                seasonId: meta.seasonId.map { SeasonID($0) },
                episodeNumber: meta.episodeNumber,
                seasonNumber: meta.seasonNumber,
                title: meta.title ?? "Unknown Episode",
                overview: meta.overview,
                runtime: meta.runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
            )
        }.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    private func selectSeason(_ season: Season) {
        guard season.id != selectedSeason?.id else { return }
        selectedSeason = season
        if offlineServerId != nil {
            loadOfflineEpisodes(for: season)
        } else {
            Task {
                await loadEpisodes(for: season)
            }
        }
    }

    // MARK: - Image Helpers

    private func backdropURL(for item: MediaItem) -> URL? {
        if offlineServerId != nil {
            if let path = offlineSeriesMetadata?.backdropImagePath {
                return DownloadStorage.shared.localImageURL(relativePath: path)
            }
            return nil
        }
        return authManager.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private var posterURL: URL? {
        if offlineServerId != nil {
            if let path = offlineSeriesMetadata?.primaryImagePath {
                return DownloadStorage.shared.localImageURL(relativePath: path)
            }
            return nil
        }
        return authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }

    private func episodeThumbnailURL(for episode: Episode) -> URL? {
        if offlineServerId != nil {
            if let meta = offlineEpisodeMetadata[episode.id.rawValue],
                let path = meta.primaryImagePath
            {
                return DownloadStorage.shared.localImageURL(relativePath: path)
            }
            return nil
        }
        return authManager.provider.imageURL(
            for: episode.id,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
    }

    // MARK: - Offline Playback

    private func playOfflineEpisode(_ episode: Episode, serverId: String) {
        guard let dm = downloadCoordinator.downloadManager,
            let dl = offlineEpisodeDownloads.first(where: { $0.itemId == episode.id }),
            let localURL = dm.localFileURL(for: dl)
        else {
            // Fallback to network
            coordinator.playEpisode(
                id: episode.id, title: episode.title, using: authManager.provider)
            return
        }
        let mediaItem = MediaItem(id: episode.id, title: episode.title, mediaType: .episode)
        coordinator.playLocal(item: mediaItem, localFileURL: localURL)
    }

    // MARK: - Offline Deletion

    private func deleteAllOfflineEpisodes() async {
        guard let dm = downloadCoordinator.downloadManager else { return }
        for ep in offlineEpisodeDownloads {
            try? await dm.deleteDownload(id: ep.id)
        }
        await loadSeasons()
    }

    private func deleteOfflineEpisode(_ dl: DownloadItem) async {
        guard let dm = downloadCoordinator.downloadManager else { return }
        try? await dm.deleteDownload(id: dl.id)
        await loadSeasons()
    }

    // MARK: - Bindings

    private var showDeleteEpisodeBinding: Binding<Bool> {
        Binding(
            get: { episodeToDelete != nil },
            set: { if !$0 { episodeToDelete = nil } }
        )
    }

    // MARK: - Download Actions

}

// MARK: - Season Picker Section

private struct SeasonPickerSection: View {
    let seasons: [Season]
    let selectedSeason: Season?
    let onSelectSeason: (Season) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(seasons) { season in
                    Button {
                        onSelectSeason(season)
                    } label: {
                        Text(season.title)
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.interpolate)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if selectedSeason?.id == season.id {
                                    Capsule()
                                        .fill(Color.accentColor)
                                } else {
                                    Capsule()
                                        .fill(.quaternary)
                                }
                            }
                            .foregroundStyle(
                                selectedSeason?.id == season.id ? .white : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.2), value: selectedSeason?.id)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Episode List Section

private struct EpisodeListSection: View {
    let isLoadingEpisodes: Bool
    let episodesError: String?
    let episodes: [Episode]
    let isOffline: Bool
    /// `true` when the currently displayed season is the earliest season in the series.
    /// Suppresses the context menu button for the first episode of the first season
    /// where there is nothing earlier to mark.
    let isFirstSeason: Bool
    let offlineEpisodeDownloads: [DownloadItem]
    let seriesId: ItemID
    let seriesName: String
    let thumbnailURL: (Episode) -> URL?
    let progress: (Episode) -> Double?
    let onPlay: (Episode) -> Void
    let onRequestDelete: (DownloadItem) -> Void
    let onMarkPreviousWatched: ((Episode) -> Void)?

    @Environment(AppState.self) private var appState

    private var coordinator: VideoPlayerCoordinator { appState.videoPlayerCoordinator }

    var body: some View {
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
                ForEach(episodes.enumerated(), id: \.element.id) { index, episode in
                    let row = EpisodeRow(
                        episode: episode,
                        thumbnailURL: thumbnailURL(episode),
                        progress: progress(episode),
                        onPlay: { onPlay(episode) }
                    )
                    .overlay {
                        if coordinator.isLoadingItem(episode.id) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .overlay { ProgressView() }
                        }
                    }

                    if isOffline {
                        row.contextMenu {
                            Button(role: .destructive) {
                                if let dl = offlineEpisodeDownloads.first(where: {
                                    $0.itemId == episode.id
                                }) {
                                    onRequestDelete(dl)
                                }
                            } label: {
                                Label("Remove Download", systemImage: "trash")
                            }
                        }
                    } else {
                        row.mediaContextMenu(
                            episode: episode,
                            seriesId: seriesId,
                            seriesName: seriesName,
                            onMarkPreviousWatched: (index > 0 || !isFirstSeason)
                                ? { onMarkPreviousWatched?(episode) } : nil
                        )
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
}

// MARK: - Season Download Sheet

private struct SeasonDownloadSheet: View {
    let seasons: [Season]
    let item: MediaItem
    let downloadingSeasons: Set<SeasonID>
    let downloadedSeasons: Set<SeasonID>
    let onDownloadSeason: (Season) async -> Void
    let onDownloadAll: () async -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await onDownloadAll() }
                    } label: {
                        HStack {
                            Label("Download All Seasons", systemImage: "arrow.down.circle.fill")
                            Spacer()
                        }
                    }
                    .disabled(!downloadingSeasons.isEmpty)
                }

                Section("Seasons") {
                    ForEach(seasons) { season in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(season.title)
                                    .font(.body)
                                if let count = season.episodeCount {
                                    Text("\(count) episode\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if downloadedSeasons.contains(season.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if downloadingSeasons.contains(season.id) {
                                ProgressView()
                            } else {
                                Button {
                                    Task { await onDownloadSeason(season) }
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title3)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Download \(item.title)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension SeriesDetailView {
    private func downloadSeason(_ season: Season) async {
        downloadingSeasons.insert(season.id)
        defer { downloadingSeasons.remove(season.id) }

        do {
            let eps = try await authManager.provider.episodes(season: season.id)
            try await downloadCoordinator.downloadSeason(
                series: item,
                season: season,
                episodes: eps
            )
            downloadedSeasons.insert(season.id)
        } catch {
            downloadError = "Failed to download \(season.title): \(error.localizedDescription)"
            showDownloadError = true
        }
    }

    private func downloadAllSeasons() async {
        for season in seasons {
            guard !downloadedSeasons.contains(season.id) else { continue }
            await downloadSeason(season)
        }
    }

    // MARK: - Progress

    private func episodeProgress(for episode: Episode) -> Double? {
        guard let runtime = episode.runtime, runtime > 0,
            let userData = episode.userData,
            userData.playbackPosition > 0
        else { return nil }
        return min(userData.playbackPosition / runtime, 1.0)
    }

    /// Marks the entire series as watched or unwatched.
    ///
    /// Jellyfin's played/unplayed endpoint is recursive — calling it on a
    /// series ID automatically propagates to all child seasons and episodes.
    private func markAllEpisodesPlayed(_ isPlayed: Bool) async {
        isMarkingSeriesWatched = true
        defer { isMarkingSeriesWatched = false }

        do {
            // Single API call — Jellyfin marks all children recursively
            try await authManager.provider.setPlayed(itemId: item.id, isPlayed: isPlayed)

            // Invalidate local overrides so fresh data is picked up
            appState.userDataStore?.invalidate(item.id)
            for episode in episodes {
                appState.userDataStore?.invalidate(episode.id)
            }

            // Reload the current season's episodes to reflect changes
            if let selectedSeason {
                await loadEpisodes(for: selectedSeason)
            }

            let message = isPlayed ? "Series marked as watched" : "Series marked as unwatched"
            let icon = isPlayed ? "eye.fill" : "eye.slash"
            ToastManager.shared.show(message, icon: icon)
        } catch {
            ToastManager.shared.show(
                "Couldn't update series", icon: "exclamationmark.triangle", style: .error)
        }
    }

    /// Marks as watched every episode that aired before the given episode:
    /// all episodes in every earlier season (via Jellyfin's recursive season-level
    /// API), plus any earlier episodes in the same season.
    ///
    /// `seasons` is already sorted ascending by season number, so filtering by
    /// `seasonNumber < episode.seasonNumber` gives us the full set of prior seasons.
    /// Calling `setPlayed` on a season ID is a single server call that Jellyfin
    /// applies recursively to every child episode — no need to fetch episode lists
    /// for those seasons.
    private func markEpisodesBeforePlayed(_ episode: Episode) async {
        guard let episodeSeasonNumber = episode.seasonNumber else { return }

        // Seasons that come entirely before the episode's season.
        let previousSeasons = seasons.filter { $0.seasonNumber < episodeSeasonNumber }

        // Episodes in the current season that come before this episode.
        let earlierInSeason: [Episode]
        if let targetIndex = episodes.firstIndex(where: { $0.id == episode.id }),
            targetIndex > 0
        {
            earlierInSeason = Array(episodes[0..<targetIndex])
        } else {
            earlierInSeason = []
        }

        guard !previousSeasons.isEmpty || !earlierInSeason.isEmpty else { return }

        do {
            // One recursive API call per prior season marks all its episodes.
            for season in previousSeasons {
                try await authManager.provider.setPlayed(itemId: season.id, isPlayed: true)
                appState.userDataStore?.invalidate(season.id)
            }

            // Mark earlier episodes in the current season individually.
            for ep in earlierInSeason {
                try await authManager.provider.setPlayed(itemId: ep.id, isPlayed: true)
                appState.userDataStore?.invalidate(ep.id)
            }

            // Reload the current season so watched indicators update immediately.
            if let selectedSeason {
                await loadEpisodes(for: selectedSeason)
            }

            let message: String
            if !previousSeasons.isEmpty && !earlierInSeason.isEmpty {
                message = "Previous seasons and episodes marked as watched"
            } else if !previousSeasons.isEmpty {
                message =
                    previousSeasons.count == 1
                    ? "Previous season marked as watched"
                    : "Previous seasons marked as watched"
            } else {
                message = "Previous episodes marked as watched"
            }
            ToastManager.shared.show(message, icon: "eye.fill")
        } catch {
            ToastManager.shared.show(
                "Couldn't update watched status",
                icon: "exclamationmark.triangle",
                style: .error
            )
        }
    }
}

// MARK: - Preview

#Preview {
    let state = AppState.preview
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
        .environment(state)
        .environment(state.authManager)
        .environment(state.downloadCoordinator)
    }
}
