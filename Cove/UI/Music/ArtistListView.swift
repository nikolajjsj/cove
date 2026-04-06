import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct ArtistListView: View {
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
            ProgressView("Loading artists…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Artists",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Artists",
                systemImage: "music.mic",
                description: Text("Your music library doesn't contain any artists yet.")
            )
        case .loaded:
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(loader.items) { artist in
                        NavigationLink(value: artist) {
                            ArtistCard(
                                name: artist.title,
                                imageURL: imageURL(for: artist)
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear { loader.onItemAppeared(artist) }
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
                    Text("\(loader.totalCount) \(loader.totalCount == 1 ? "artist" : "artists")")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 24)
                }
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
                includeItemTypes: ["MusicArtist"]
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

// MARK: - Artist Card

private struct ArtistCard: View {
    let name: String
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 8) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ArtistListView(library: nil)
            .environment(AppState())
    }
}
