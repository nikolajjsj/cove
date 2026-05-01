import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct GenreDetailView: View {
    let genreItem: MediaItem
    let library: MediaLibrary?
    @Default(.gridDensity) private var gridDensity
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = PagedCollectionLoader<MediaItem>()

    private let pageSize = 40

    /// Resolves the music library — uses the explicitly provided one, or falls back
    /// to the first music library found in AppState (covers the NavigationRouter case
    /// where library is nil).
    private var resolvedLibrary: MediaLibrary? {
        library ?? appState.libraries.first { $0.collectionType == .music }
    }

    var body: some View {
        GenreDetailContent(
            loader: loader,
            onItemAppeared: { loader.onItemAppeared($0) }
        )
        .navigationTitle(genreItem.title)
        .largeNavigationTitle()
        .task(id: genreItem.id) { await loadFirstPage() }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library = resolvedLibrary else {
            loader.reset()
            return
        }

        let provider = authManager.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions(
                genres: [genreItem.title],
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: ["MusicAlbum"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Genre Detail Content

private struct GenreDetailContent: View {
    let loader: PagedCollectionLoader<MediaItem>
    let onItemAppeared: (MediaItem) -> Void

    @Environment(AuthManager.self) private var authManager
    @Default(.gridDensity) private var gridDensity

    var body: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading albums…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Albums",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Albums",
                systemImage: "square.stack",
                description: Text("No albums found in this genre.")
            )
        case .loaded:
            ScrollView {
                LazyVGrid(
                    columns: gridDensity.columns,
                    spacing: gridDensity.gridSpacing
                ) {
                    ForEach(loader.items) { album in
                        AlbumCard(
                            item: album,
                            subtitle: album.genres?.first,
                            imageURL: imageURL(for: album)
                        )
                        .onAppear { onItemAppeared(album) }
                    }
                }
                .padding()

                if loader.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 16)
                        Spacer()
                    }
                }

                if !loader.items.isEmpty && !loader.hasMore && loader.totalCount > 0 {
                    Text(
                        "\(loader.totalCount) \(loader.totalCount == 1 ? "album" : "albums")"
                    )
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        GenreDetailView(
            genreItem: MediaItem(id: ItemID("preview"), title: "Rock", mediaType: .genre),
            library: nil
        )
        .environment(state)
        .environment(state.authManager)
    }
}
