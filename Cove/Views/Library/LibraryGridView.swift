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

    // MARK: - Sort & Filter State

    @State private var sortField: SortField = .name
    @State private var sortOrder: Models.SortOrder = .ascending
    @State private var watchedFilter: WatchedFilter = .all

    /// Number of items to fetch per page.
    private let pageSize = 40

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    // MARK: - Watched Filter

    private enum WatchedFilter: String, Hashable, CaseIterable {
        case all
        case unwatched
        case watched

        var label: String {
            switch self {
            case .all: "All"
            case .unwatched: "Unwatched"
            case .watched: "Watched"
            }
        }

        var systemImage: String {
            switch self {
            case .all: "line.3.horizontal.decrease.circle"
            case .unwatched: "eye.slash"
            case .watched: "eye"
            }
        }
    }

    // MARK: - Computed Helpers

    private var sortOptions: SortOptions {
        SortOptions(field: sortField, order: sortOrder)
    }

    private var isPlayedFilter: Bool? {
        switch watchedFilter {
        case .all: nil
        case .unwatched: false
        case .watched: true
        }
    }

    private var sortFieldLabel: String {
        switch sortField {
        case .name: "Name"
        case .dateAdded: "Date Added"
        case .premiereDate: "Release Date"
        case .communityRating: "Rating"
        case .runtime: "Runtime"
        default: "Name"
        }
    }

    var body: some View {
        Group {
            if isActivelySearching {
                searchContent
            } else {
                mainContent
            }
        }
        .searchable(text: $searchText, prompt: "Search this library…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sortMenu
            }
        }
        .task(id: library?.id) {
            await loadFirstPage()
        }
        .task(id: searchText) {
            await performLibrarySearch()
        }
        .onChange(of: sortField) { _, _ in
            reloadAfterFilterChange()
        }
        .onChange(of: sortOrder) { _, _ in
            reloadAfterFilterChange()
        }
        .onChange(of: watchedFilter) { _, _ in
            reloadAfterFilterChange()
        }
    }

    private var isActivelySearching: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortField) {
                Text("Name").tag(SortField.name)
                Text("Date Added").tag(SortField.dateAdded)
                Text("Release Date").tag(SortField.premiereDate)
                Text("Rating").tag(SortField.communityRating)
                Text("Runtime").tag(SortField.runtime)
            }

            Divider()

            Picker("Order", selection: $sortOrder) {
                Label("Ascending", systemImage: "arrow.up")
                    .tag(Models.SortOrder.ascending)
                Label("Descending", systemImage: "arrow.down")
                    .tag(Models.SortOrder.descending)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Filter Chip Bar

    @ViewBuilder
    private var filterChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                watchedChip
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var watchedChip: some View {
        Menu {
            Picker("Status", selection: $watchedFilter) {
                ForEach(WatchedFilter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
        } label: {
            Label(
                watchedFilter == .all ? "Watched Status" : watchedFilter.label,
                systemImage: watchedFilter.systemImage
            )
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(watchedFilter != .all ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
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
            filterChipBar

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
            .padding(.horizontal)

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

    // MARK: - Filter Change Reload

    /// Resets the loader and search state, then reloads content using the
    /// current sort and filter settings. Called from `.onChange` handlers
    /// so that every sort/filter picker change is immediately reflected.
    private func reloadAfterFilterChange() {
        loader.reset()
        searchResults = []
        searchTotalCount = 0
        searchHasMore = false

        Task {
            if isActivelySearching {
                await performLibrarySearch()
            } else {
                await loadFirstPage()
            }
        }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = authManager.provider
        let sort = sortOptions
        let played = isPlayedFilter

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let filter = await FilterOptions(
                isPlayed: played,
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

        let sort = sortOptions
        let filter = FilterOptions(
            isPlayed: isPlayedFilter,
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

        let sort = sortOptions
        let filter = FilterOptions(
            isPlayed: isPlayedFilter,
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
