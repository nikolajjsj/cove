import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct LibraryGridView: View {
    let library: MediaLibrary?
    @Environment(AuthManager.self) private var authManager
    @State private var loader = PagedCollectionLoader<MediaItem>()
    @State private var searchText = ""
    @State private var searchResults: [MediaItem] = []
    @State private var isSearchingLibrary = false
    @State private var searchTotalCount = 0
    @State private var searchHasMore = false
    @State private var isSearchLoadingMore = false

    /// Number of items to fetch per page.
    private let pageSize = 40

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        Group {
            if isActivelySearching {
                searchContent
            } else {
                mainContent
            }
        }
        .searchable(text: $searchText, prompt: "Search this library…")
        .task(id: library?.id) {
            await loadFirstPage()
        }
        .task(id: searchText) {
            await performLibrarySearch()
        }
    }

    private var isActivelySearching: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Items",
                systemImage: "tray",
                description: Text("This library is empty.")
            )
        case .loaded:
            scrollContent
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(loader.items) { item in
                    NavigationLink(value: item) {
                        LibraryItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        loader.onItemAppeared(item)
                    }
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
                Text("\(loader.totalCount) \(itemNoun)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Search Content

    @ViewBuilder
    private var searchContent: some View {
        if isSearchingLibrary && searchResults.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty && !isSearchingLibrary {
            ContentUnavailableView.search(text: searchText)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(searchResults) { item in
                        NavigationLink(value: item) {
                            LibraryItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear { onSearchItemAppeared(item) }
                    }
                }
                .padding()

                if isSearchLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 16)
                        Spacer()
                    }
                }

                if !searchResults.isEmpty && !searchHasMore && searchTotalCount > 0 {
                    Text("\(searchTotalCount) \(searchTotalCount == 1 ? "result" : "results")")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Search Pagination Trigger

    private func onSearchItemAppeared(_ item: MediaItem) {
        guard searchHasMore, !isSearchLoadingMore else { return }
        let thresholdIndex = max(searchResults.count - 10, 0)
        guard let index = searchResults.firstIndex(where: { $0.id == item.id }),
            index >= thresholdIndex
        else { return }
        Task { await loadNextSearchPage() }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = authManager.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions(
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: library.includeItemTypes
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Search

    private func performLibrarySearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2, let library else {
            searchResults = []
            return
        }

        isSearchingLibrary = true
        defer { isSearchingLibrary = false }

        // Debounce 300ms
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch { return }

        let sort = SortOptions(field: .name, order: .ascending)
        let filter = FilterOptions(
            limit: pageSize,
            startIndex: 0,
            searchTerm: query,
            includeItemTypes: library.includeItemTypes
        )

        do {
            let result = try await authManager.provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            searchResults = result.items
            searchTotalCount = result.totalCount
            searchHasMore = result.hasMore
        } catch {
            if !Task.isCancelled {
                searchResults = []
            }
        }
    }

    private func loadNextSearchPage() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard let library, searchHasMore, !isSearchLoadingMore else { return }

        isSearchLoadingMore = true

        let sort = SortOptions(field: .name, order: .ascending)
        let filter = FilterOptions(
            limit: pageSize,
            startIndex: searchResults.count,
            searchTerm: query,
            includeItemTypes: library.includeItemTypes
        )

        do {
            let result = try await authManager.provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            let existingIDs = Set(searchResults.map(\.id))
            let newItems = result.items.filter { !existingIDs.contains($0.id) }
            searchResults.append(contentsOf: newItems)
            searchTotalCount = result.totalCount
            searchHasMore = result.hasMore
        } catch {
            searchHasMore = false
        }

        isSearchLoadingMore = false
    }

    // MARK: - Helpers

    private var itemNoun: String {
        guard let collectionType = library?.collectionType else { return "items" }
        switch collectionType {
        case .movies: return loader.totalCount == 1 ? "movie" : "movies"
        case .tvshows: return loader.totalCount == 1 ? "show" : "shows"
        case .music: return loader.totalCount == 1 ? "item" : "items"
        case .boxsets: return loader.totalCount == 1 ? "collection" : "collections"
        default: return loader.totalCount == 1 ? "item" : "items"
        }
    }
}
