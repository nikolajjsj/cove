import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct SongListView: View {
    let library: MediaLibrary?
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = PagedCollectionLoader<MediaItem>()

    private let pageSize = 40

    var body: some View {
        SongListContent(
            loader: loader,
            onPlay: playFromIndex,
            onItemAppeared: { loader.onItemAppeared($0) }
        )
        .task(id: "\(library?.id.rawValue ?? "")-\(sortField)-\(sortOrder)-\(isFavoriteFilter)") {
            await loadFirstPage()
        }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = authManager.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: sortField, order: sortOrder)
            let filter = FilterOptions(
                isFavorite: isFavoriteFilter ? true : Optional<Bool>.none,
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: ["Audio"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Playback

    private func playFromIndex(_ index: Int) {
        let tracks = loader.items.map { $0.asTrack }
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func isCurrentTrack(_ item: MediaItem) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id.rawValue == item.id.rawValue
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 80, height: 80)
        )
    }
}

// MARK: - Song List Content

private struct SongListContent: View {
    let loader: PagedCollectionLoader<MediaItem>
    let onPlay: (Int) -> Void
    let onItemAppeared: (MediaItem) -> Void

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading songs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Songs",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Songs",
                systemImage: "music.note",
                description: Text("Your music library doesn't contain any songs yet.")
            )
        case .loaded:
            List {
                ForEach(loader.items.enumerated(), id: \.element.id) { index, item in
                    TrackRow(
                        title: item.title,
                        subtitle: item.genres?.first,
                        imageURL: imageURL(for: item),
                        duration: item.runtime,
                        isCurrentTrack: isCurrentTrack(item),
                        isPlaying: isCurrentTrack(item) && appState.audioPlayer.isPlaying,
                        isFavorite: appState.userDataStore?.isFavorite(
                            item.id, fallback: item.userData
                        ) ?? item.userData?.isFavorite ?? false,
                        onTap: { onPlay(index) }
                    )
                    .onAppear { onItemAppeared(item) }
                    .mediaContextMenu(item: item)
                }

                if loader.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 8)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }

                if !loader.items.isEmpty && !loader.hasMore && loader.totalCount > 0 {
                    Text(
                        "\(loader.totalCount) \(loader.totalCount == 1 ? "song" : "songs")"
                    )
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.plain)
        }
    }

    private func isCurrentTrack(_ item: MediaItem) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id.rawValue == item.id.rawValue
    }

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 80, height: 80)
        )
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        SongListView(library: nil)
            .environment(state)
            .environment(state.authManager)
    }
}
