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
            } else if isLoading && items.isEmpty {
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
            includeItemTypes: library.includeItemTypes,
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
            includeItemTypes: library.includeItemTypes,
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
            let result = try await appState.provider.pagedItems(
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
            let result = try await appState.provider.pagedItems(
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
        case .movies: return totalCount == 1 ? "movie" : "movies"
        case .tvshows: return totalCount == 1 ? "show" : "shows"
        case .music: return totalCount == 1 ? "item" : "items"
        case .boxsets: return totalCount == 1 ? "collection" : "collections"
        default: return totalCount == 1 ? "item" : "items"
        }
    }
}
