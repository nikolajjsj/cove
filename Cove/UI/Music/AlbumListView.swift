import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct AlbumListView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var loader = PagedCollectionLoader<MediaItem>()

    /// Number of items to fetch per page.
    private let pageSize = 40

    var body: some View {
        Group {
            mainContent
        }
        .task(id: library?.id) { await loadFirstPage() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
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
                description: Text("Your music library doesn't contain any albums yet.")
            )
        case .loaded:
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)],
                spacing: 20
            ) {
                ForEach(loader.items) { album in
                    NavigationLink(value: album) {
                        AlbumCard(
                            title: album.title,
                            imageURL: imageURL(for: album)
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear { loader.onItemAppeared(album) }
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
                Text("\(loader.totalCount) \(loader.totalCount == 1 ? "album" : "albums")")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = appState.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions(
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
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Album Card

private struct AlbumCard: View {
    let title: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        AlbumListView(library: nil)
            .environment(AppState())
    }
}
