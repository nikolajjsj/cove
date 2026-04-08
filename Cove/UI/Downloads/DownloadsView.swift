import DownloadManager
import Models
import Persistence
import SwiftUI

/// The main downloads page with a hybrid layout:
/// Active/failed downloads at the top, then completed content organized as a mini library.
struct DownloadsView: View {
    let downloadManager: DownloadManagerService

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @State private var viewModel: DownloadsViewModel?
    @State private var showStorageManagement = false
    @State private var showDeleteAllConfirmation = false
    @State private var itemToDelete: DownloadItem?
    @State private var groupToDelete: (id: String, title: String, count: Int, size: Int64)?
    @State private var seriesToDelete: (seriesId: String, title: String, count: Int, size: Int64)?
    @State private var albumToDelete: (albumId: String, title: String, count: Int, size: Int64)?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView("Loading downloads…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    downloadsContent(viewModel)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        showStorageManagement = true
                    } label: {
                        Label("Storage", systemImage: "internaldrive")
                    }

                    if let viewModel, !viewModel.isEmpty {
                        Divider()

                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showStorageManagement) {
            NavigationStack {
                StorageManagementView(downloadManager: downloadManager)
            }
        }
        .confirmationDialog(
            "Delete All Downloads?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await viewModel?.deleteAllDownloads() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All downloaded media will be removed from your device. This cannot be undone.")
        }
        .alert("Delete Download?", isPresented: showDeleteItemBinding) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { await viewModel?.deleteDownload(item) }
                    itemToDelete = nil
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("'\(item.title)' will be removed from your device.")
            }
        }
        .confirmationDialog(
            groupToDelete.map { "Remove \($0.title)?" } ?? "Remove?",
            isPresented: showDeleteGroupBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let group = groupToDelete {
                    Task { await viewModel?.deleteGroup(id: group.id) }
                    groupToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { groupToDelete = nil }
        } message: {
            if let group = groupToDelete {
                let sizeStr = ByteCountFormatter.string(
                    fromByteCount: group.size, countStyle: .file)
                Text("All \(group.count) items (\(sizeStr)) will be removed from your device.")
            }
        }
        .confirmationDialog(
            seriesToDelete.map { "Remove \($0.title)?" } ?? "Remove?",
            isPresented: showDeleteSeriesBinding,
            titleVisibility: .visible
        ) {
            Button("Remove All Episodes", role: .destructive) {
                if let series = seriesToDelete {
                    Task { await viewModel?.deleteSeriesEpisodes(seriesId: series.seriesId) }
                    seriesToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { seriesToDelete = nil }
        } message: {
            if let series = seriesToDelete {
                let sizeStr = ByteCountFormatter.string(
                    fromByteCount: series.size, countStyle: .file)
                Text(
                    "All \(series.count) episode\(series.count == 1 ? "" : "s") (\(sizeStr)) will be removed from your device."
                )
            }
        }
        .confirmationDialog(
            albumToDelete.map { "Remove \($0.title)?" } ?? "Remove?",
            isPresented: showDeleteAlbumBinding,
            titleVisibility: .visible
        ) {
            Button("Remove All Tracks", role: .destructive) {
                if let album = albumToDelete {
                    Task { await viewModel?.deleteAlbumTracks(albumId: album.albumId) }
                    albumToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { albumToDelete = nil }
        } message: {
            if let album = albumToDelete {
                let sizeStr = ByteCountFormatter.string(
                    fromByteCount: album.size, countStyle: .file)
                Text(
                    "All \(album.count) track\(album.count == 1 ? "" : "s") (\(sizeStr)) will be removed from your device."
                )
            }
        }
        .task {
            guard let connection = authManager.activeConnection else { return }
            let vm = DownloadsViewModel(
                downloadManager: downloadManager,
                metadataRepository: downloadCoordinator.offlineMetadataRepository,
                groupRepository: downloadCoordinator.downloadGroupRepository,
                downloadRepository: downloadCoordinator.downloadRepository
            )
            viewModel = vm
            vm.startObserving(serverId: connection.id.uuidString)
        }
        .navigationDestination(for: OfflineSeriesDestination.self) { destination in
            SeriesDetailView(
                offlineSeriesId: destination.seriesId,
                serverId: destination.serverId,
                title: destination.title
            )
        }
        .navigationDestination(for: OfflineAlbumDestination.self) { destination in
            AlbumDetailView(
                offlineAlbumId: destination.albumId,
                serverId: destination.serverId,
                title: destination.title
            )
        }
        .onDisappear {
            viewModel?.stopObserving()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Downloads",
            systemImage: "arrow.down.circle",
            description: Text("Download music, movies, and episodes to enjoy offline.")
        )
    }

    // MARK: - Main Content

    @ViewBuilder
    private func downloadsContent(_ vm: DownloadsViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Section 1: Active + Failed downloads
                if vm.hasInProgressOrFailed {
                    activeAndFailedSection(vm)
                }

                // Section 2: Movies
                if !vm.completedMovies.isEmpty {
                    moviesSection(vm)
                }

                // Section 3: TV Shows
                if !vm.completedSeriesGroups.isEmpty {
                    tvShowsSection(vm)
                }

                // Section 4: Music
                if !vm.completedMusicByArtist.isEmpty {
                    musicSection(vm)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Section 1: Active + Failed

    @ViewBuilder
    private func activeAndFailedSection(_ vm: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Downloads")
                Spacer()
                if !vm.activeDownloads.isEmpty {
                    Text("\(vm.activeDownloads.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            LazyVStack(spacing: 0) {
                ForEach(vm.activeDownloads) { item in
                    DownloadRowView(item: item) { action, item in
                        handleAction(action, item, vm: vm)
                    }
                    .padding(.horizontal)
                    Divider().padding(.leading)
                }

                if !vm.failedDownloads.isEmpty && !vm.activeDownloads.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                }

                ForEach(vm.failedDownloads) { item in
                    DownloadRowView(item: item) { action, item in
                        handleAction(action, item, vm: vm)
                    }
                    .padding(.horizontal)
                    Divider().padding(.leading)
                }

                if vm.failedDownloads.count > 1 {
                    Button("Retry All Failed") {
                        Task { await vm.retryAllFailed() }
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Section 2: Movies

    private let movieColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    @ViewBuilder
    private func moviesSection(_ vm: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Movies")
                .padding(.horizontal)

            LazyVGrid(columns: movieColumns, spacing: 20) {
                ForEach(vm.completedMovies) { item in
                    Button {
                        playOfflineMovie(item, vm: vm)
                    } label: {
                        offlinePosterCard(
                            title: vm.metadataByItemId[item.itemId.rawValue]?.title ?? item.title,
                            imageURL: vm.localPrimaryImageURL(for: item.itemId.rawValue),
                            aspectRatio: 2.0 / 3.0,
                            icon: "film"
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            itemToDelete = item
                        } label: {
                            let size = ByteCountFormatter.string(
                                fromByteCount: item.totalBytes, countStyle: .file)
                            Label("Remove Download (\(size))", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Section 3: TV Shows

    private let tvColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    @ViewBuilder
    private func tvShowsSection(_ vm: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TV Shows")
                .padding(.horizontal)

            LazyVGrid(columns: tvColumns, spacing: 20) {
                ForEach(vm.completedSeriesGroups, id: \.series.itemId) { group in
                    NavigationLink(
                        value: OfflineSeriesDestination(
                            seriesId: group.series.itemId,
                            serverId: group.series.serverId,
                            title: group.series.title ?? "Unknown Series"
                        )
                    ) {
                        offlinePosterCard(
                            title: group.series.title ?? "Unknown Series",
                            subtitle:
                                "\(group.episodes.count) episode\(group.episodes.count == 1 ? "" : "s")",
                            imageURL: vm.localPrimaryImageURL(for: group.series.itemId),
                            aspectRatio: 2.0 / 3.0,
                            icon: "tv"
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            let totalSize = group.episodes.reduce(Int64(0)) {
                                $0 + $1.totalBytes
                            }
                            seriesToDelete = (
                                seriesId: group.series.itemId,
                                title: group.series.title ?? "Unknown Series",
                                count: group.episodes.count,
                                size: totalSize
                            )
                        } label: {
                            Label("Remove Series", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Section 4: Music

    private let musicColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    @ViewBuilder
    private func musicSection(_ vm: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Music")
                .padding(.horizontal)

            ForEach(vm.completedMusicByArtist, id: \.artist) { artistGroup in
                VStack(alignment: .leading, spacing: 12) {
                    // Artist header
                    Text(artistGroup.artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: musicColumns, spacing: 20) {
                        ForEach(artistGroup.albums, id: \.album.itemId) { albumGroup in
                            NavigationLink(
                                value: OfflineAlbumDestination(
                                    albumId: albumGroup.album.itemId,
                                    serverId: albumGroup.album.serverId,
                                    title: albumGroup.album.title ?? "Unknown Album"
                                )
                            ) {
                                offlineAlbumCard(
                                    title: albumGroup.album.title ?? "Unknown Album",
                                    subtitle:
                                        "\(albumGroup.tracks.count) track\(albumGroup.tracks.count == 1 ? "" : "s")",
                                    imageURL: vm.localPrimaryImageURL(for: albumGroup.album.itemId)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    let totalSize = albumGroup.tracks.reduce(Int64(0)) {
                                        $0 + $1.totalBytes
                                    }
                                    albumToDelete = (
                                        albumId: albumGroup.album.itemId,
                                        title: albumGroup.album.title ?? "Unknown Album",
                                        count: albumGroup.tracks.count,
                                        size: totalSize
                                    )
                                } label: {
                                    Label("Remove Album", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Card Components

    private func offlinePosterCard(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        aspectRatio: CGFloat,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.poster(
                url: imageURL,
                aspectRatio: aspectRatio,
                icon: icon,
                cornerRadius: 8
            )

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func offlineAlbumCard(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .bold()
    }

    // MARK: - Actions

    private func handleAction(
        _ action: DownloadAction, _ item: DownloadItem, vm: DownloadsViewModel
    ) {
        Task {
            switch action {
            case .pause:
                await vm.pauseDownload(item)
            case .resume:
                await vm.resumeDownload(item)
            case .retry:
                await vm.retryDownload(item)
            case .delete:
                itemToDelete = item
            case .play:
                // Playback integration — to be wired in a later phase
                break
            }
        }
    }

    /// Build a `MediaItem` from offline metadata and play it from the local file.
    private func playOfflineMovie(_ item: DownloadItem, vm: DownloadsViewModel) {
        let meta = vm.metadataByItemId[item.itemId.rawValue]

        let userData: UserData? = {
            if let pos = meta?.playbackPosition {
                return UserData(
                    isFavorite: meta?.isFavorite ?? false,
                    playbackPosition: pos,
                    playCount: meta?.playCount ?? 0,
                    isPlayed: meta?.isPlayed ?? false
                )
            }
            return nil
        }()

        let mediaItem = MediaItem(
            id: item.itemId,
            title: meta?.title ?? item.title,
            overview: meta?.overview,
            mediaType: .movie,
            productionYear: meta?.productionYear,
            runTimeTicks: meta?.runTimeTicks,
            communityRating: meta?.communityRating,
            officialRating: meta?.officialRating,
            userData: userData
        )

        if let localURL = downloadManager.localFileURL(for: item) {
            appState.videoPlayerCoordinator.playLocal(item: mediaItem, localFileURL: localURL)
        } else {
            // Fallback: try to play via network
            appState.videoPlayerCoordinator.play(item: mediaItem, using: authManager.provider)
        }
    }

    // MARK: - Bindings

    private var showDeleteItemBinding: Binding<Bool> {
        Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )
    }

    private var showDeleteGroupBinding: Binding<Bool> {
        Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        )
    }

    private var showDeleteSeriesBinding: Binding<Bool> {
        Binding(
            get: { seriesToDelete != nil },
            set: { if !$0 { seriesToDelete = nil } }
        )
    }

    private var showDeleteAlbumBinding: Binding<Bool> {
        Binding(
            get: { albumToDelete != nil },
            set: { if !$0 { albumToDelete = nil } }
        )
    }
}

// MARK: - Navigation Destinations

/// Navigation value for offline series detail.
struct OfflineSeriesDestination: Hashable {
    let seriesId: String
    let serverId: String
    let title: String
}

/// Navigation value for offline album detail.
struct OfflineAlbumDestination: Hashable {
    let albumId: String
    let serverId: String
    let title: String
}
