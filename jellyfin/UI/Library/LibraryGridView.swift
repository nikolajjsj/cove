import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct LibraryGridView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalCount = 0
    @State private var hasMore = false
    @State private var errorMessage: String?

    /// Number of items to fetch per page.
    private let pageSize = 40

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("This library is empty.")
                )
            } else {
                scrollContent
            }
        }
        .navigationDestination(for: MediaItem.self) { item in
            destinationView(for: item)
        }
        .task(id: library?.id) {
            await loadFirstPage()
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        LibraryItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        onItemAppeared(item)
                    }
                }
            }
            .padding()

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 16)
                    Spacer()
                }
            }

            if !items.isEmpty && !hasMore && totalCount > 0 {
                Text("\(totalCount) \(itemNoun)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Pagination Trigger

    /// When an item appears on screen, check if we need to pre-fetch the next page.
    /// We trigger the load when the user scrolls within the last 10 items.
    private func onItemAppeared(_ item: MediaItem) {
        guard hasMore, !isLoadingMore else { return }

        let thresholdIndex = max(items.count - 10, 0)
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            index >= thresholdIndex
        else {
            return
        }

        Task {
            await loadNextPage()
        }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        items = []

        let sort = SortOptions(field: .name, order: .ascending)
        let filter = FilterOptions(
            limit: pageSize,
            startIndex: 0,
            includeItemTypes: includeItemTypes(for: library),
        )

        do {
            let result = try await appState.provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            items = result.items
            totalCount = result.totalCount
            hasMore = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }

        isLoading = false
    }

    private func loadNextPage() async {
        guard let library, hasMore, !isLoadingMore else { return }

        isLoadingMore = true

        let sort = SortOptions(field: .name, order: .ascending)
        let filter = FilterOptions(
            limit: pageSize,
            startIndex: items.count,
            includeItemTypes: includeItemTypes(for: library),
        )

        do {
            let result = try await appState.provider.pagedItems(
                in: library, sort: sort, filter: filter
            )

            // Deduplicate by ID in case the server shifts items between pages
            let existingIDs = Set(items.map(\.id))
            let newItems = result.items.filter { !existingIDs.contains($0.id) }

            items.append(contentsOf: newItems)
            totalCount = result.totalCount
            hasMore = result.hasMore
        } catch {
            // On pagination failure, just stop paging — don't clear existing items
            hasMore = false
        }

        isLoadingMore = false
    }

    // MARK: - Item Type Filtering

    /// Returns the Jellyfin `IncludeItemTypes` values appropriate for each library type.
    /// This ensures the TV Shows library returns only Series (not Seasons/Episodes),
    /// the Movies library returns only Movies, etc.
    private func includeItemTypes(for library: MediaLibrary) -> [String]? {
        switch library.collectionType {
        case .movies:
            return ["Movie"]
        case .tvshows:
            return ["Series"]
        case .music:
            // Music library should show albums and artists at the top level
            return nil
        default:
            return nil
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destinationView(for item: MediaItem) -> some View {
        switch item.mediaType {
        case .movie:
            MovieDetailView(item: item)
        case .series:
            SeriesDetailView(item: item)
        case .artist:
            ArtistDetailView(artistItem: item)
        case .album:
            AlbumDetailView(albumItem: item)
        default:
            Text(item.title)
                .navigationTitle(item.title)
        }
    }

    // MARK: - Helpers

    private var itemNoun: String {
        guard let collectionType = library?.collectionType else { return "items" }
        switch collectionType {
        case .movies: return totalCount == 1 ? "movie" : "movies"
        case .tvshows: return totalCount == 1 ? "show" : "shows"
        case .music: return totalCount == 1 ? "item" : "items"
        default: return totalCount == 1 ? "item" : "items"
        }
    }
}
