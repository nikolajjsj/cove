import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

// MARK: - Library Grid

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
    @State private var selectedGenres: Set<String> = []
    @State private var availableGenres: [String] = []
    @State private var favoriteOnly: Bool = false
    @State private var selectedDecade: Decade? = nil
    @State private var minRating: Double? = nil

    /// Number of items to fetch per page.
    private let pageSize = 40

    @Default(.gridDensity) private var gridDensity
    @Default(.videoLibraryLayout) private var videoLayout
    @Default(.musicLibraryLayout) private var musicLayout

    private var layoutMode: LibraryLayoutMode {
        isVideoLibrary ? videoLayout : musicLayout
    }

    // MARK: - SearchKey

    /// Bundles all state that should restart the search task into one Equatable value.
    /// Using this as the task ID means a single `task(id: searchKey)` replaces all
    /// the separate `onChange` handlers for search, eliminating the race condition
    /// where `reloadAfterFilterChange` spawned a bare Task alongside the managed task.
    private struct SearchKey: Equatable {
        var query: String
        var sortField: SortField
        var sortOrder: Models.SortOrder
        var watchedFilter: WatchedFilter
        var selectedGenres: Set<String>
        var favoriteOnly: Bool
        var selectedDecade: Decade?
        var minRating: Double?
    }

    // MARK: - Computed Helpers

    private var sortOptions: SortOptions {
        SortOptions(field: sortField, order: sortOrder)
    }

    private var searchKey: SearchKey {
        SearchKey(
            query: searchText,
            sortField: sortField,
            sortOrder: sortOrder,
            watchedFilter: watchedFilter,
            selectedGenres: selectedGenres,
            favoriteOnly: favoriteOnly,
            selectedDecade: selectedDecade,
            minRating: minRating
        )
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
                Button(
                    layoutMode == .grid ? "List" : "Grid",
                    systemImage: layoutMode == .grid ? "list.bullet" : "square.grid.2x2"
                ) {
                    toggleLayout()
                }
                sortMenu
            }
        }
        .task(id: library?.id) {
            await loadFirstPage()
        }
        .task(id: library?.id) {
            availableGenres = []
            selectedGenres = []
            favoriteOnly = false
            selectedDecade = nil
            minRating = nil
            guard isVideoLibrary, let library else { return }
            await loadGenres(for: library)
        }
        .task(id: searchKey) {
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
        .onChange(of: selectedGenres) { _, _ in
            reloadAfterFilterChange()
        }
        .onChange(of: favoriteOnly) { _, _ in
            reloadAfterFilterChange()
        }
        .onChange(of: selectedDecade) { _, _ in
            reloadAfterFilterChange()
        }
        .onChange(of: minRating) { _, _ in
            reloadAfterFilterChange()
        }
    }

    /// Whether this library supports genre browsing (movies or TV shows).
    private var isVideoLibrary: Bool {
        switch library?.collectionType {
        case .movies, .tvshows:
            true
        default:
            false
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

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Chip bar is always visible regardless of phase so the user can
            // always see which filters are active and toggle them off.
            FilterChipBar(
                watchedFilter: $watchedFilter,
                favoriteOnly: $favoriteOnly,
                selectedGenres: $selectedGenres,
                selectedDecade: $selectedDecade,
                minRating: $minRating,
                isVideoLibrary: isVideoLibrary,
                availableGenres: availableGenres
            )
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                scrollContent
            }
        }
    }

    // MARK: - Context-Aware Empty State

    private var hasActiveFilters: Bool {
        watchedFilter != .all
            || favoriteOnly
            || !selectedGenres.isEmpty
            || selectedDecade != nil
            || minRating != nil
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if favoriteOnly {
            ContentUnavailableView(
                "No Favorites",
                systemImage: "heart",
                description: Text(
                    "You haven't marked any items as favorites yet. Tap the heart on any movie or show to add it here."
                )
            )
        } else if hasActiveFilters {
            ContentUnavailableView(
                "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(
                    "No items match the current filters. Try adjusting or removing some filters.")
            )
        } else {
            ContentUnavailableView(
                "No Items",
                systemImage: "tray",
                description: Text("This library is empty.")
            )
        }
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        if layoutMode == .list {
            List {
                ForEach(loader.items) { item in
                    NavigationLink(value: item) {
                        MediaListRow(item: item)
                    }
                    .onAppear {
                        loader.onItemAppeared(item)
                    }
                }

                if loader.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if !loader.items.isEmpty && !loader.hasMore && loader.totalCount > 0 {
                    Text("\(loader.totalCount) \(itemNoun)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
        } else {
            ScrollView {
                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(loader.items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item)
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
    }

    // MARK: - Search Content

    @ViewBuilder
    private var searchContent: some View {
        if isSearchingLibrary && searchResults.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty && !isSearchingLibrary {
            ContentUnavailableView.search(text: searchText)
        } else if layoutMode == .list {
            List {
                ForEach(searchResults) { item in
                    NavigationLink(value: item) {
                        MediaListRow(item: item)
                    }
                    .onAppear { onSearchItemAppeared(item) }
                }

                if isSearchLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if !searchResults.isEmpty && !searchHasMore && searchTotalCount > 0 {
                    Text("\(searchTotalCount) \(searchTotalCount == 1 ? "result" : "results")")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
        } else {
            ScrollView {
                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(searchResults) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item)
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

    private func toggleLayout() {
        if isVideoLibrary {
            videoLayout = videoLayout == .grid ? .list : .grid
        } else {
            musicLayout = musicLayout == .grid ? .list : .grid
        }
    }

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

        if !isActivelySearching {
            Task { await loadFirstPage() }
        }
        // If isActivelySearching, task(id: searchKey) will restart automatically
        // because searchKey changed, cancelling the prior search task.
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
        let genres = selectedGenres.isEmpty ? nil : Array(selectedGenres)
        let favorite = favoriteOnly ? true : nil
        let years = selectedDecade?.years
        let rating = minRating

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let filter = FilterOptions(
                genres: genres,
                years: years,
                isFavorite: favorite,
                isPlayed: played,
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: library.includeItemTypes,
                minCommunityRating: rating
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    private func loadGenres(for library: MediaLibrary) async {
        do {
            let items = try await authManager.provider.genres(in: library)
            availableGenres = items.map(\.title)
        } catch {
            availableGenres = []
        }
    }

    // MARK: - Search Filter

    /// Builds a consistent `FilterOptions` for search requests, capturing all
    /// active filters so that both the first page and subsequent pages use
    /// identical criteria.
    private func currentSearchFilter(query: String, startIndex: Int) -> FilterOptions {
        FilterOptions(
            genres: selectedGenres.isEmpty ? nil : Array(selectedGenres),
            years: selectedDecade?.years,
            isFavorite: favoriteOnly ? true : nil,
            isPlayed: isPlayedFilter,
            limit: pageSize,
            startIndex: startIndex,
            searchTerm: query,
            includeItemTypes: library?.includeItemTypes,
            minCommunityRating: minRating
        )
    }

    // MARK: - Search

    private func performLibrarySearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2, let library else {
            searchResults = []
            return
        }

        // Debounce — if searchKey changes again, this task is cancelled here.
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        // Only show the spinner after the debounce window passes.
        isSearchingLibrary = true
        defer { isSearchingLibrary = false }

        let sort = sortOptions
        let filter = currentSearchFilter(query: query, startIndex: 0)

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
        let filter = currentSearchFilter(query: query, startIndex: searchResults.count)

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

// MARK: - Filter Chip Bar

private struct FilterChipBar: View {
    @Binding var watchedFilter: WatchedFilter
    @Binding var favoriteOnly: Bool
    @Binding var selectedGenres: Set<String>
    @Binding var selectedDecade: Decade?
    @Binding var minRating: Double?
    let isVideoLibrary: Bool
    let availableGenres: [String]

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: always shown
            HStack(spacing: 8) {
                WatchedFilterChip(selection: $watchedFilter)
                    .frame(maxWidth: .infinity)
                FavoriteChip(isOn: $favoriteOnly)
                    .frame(maxWidth: .infinity)
            }

            if isVideoLibrary {
                // Row 2: content filters
                HStack(spacing: 8) {
                    if !availableGenres.isEmpty {
                        GenreChip(
                            selectedGenres: $selectedGenres,
                            availableGenres: availableGenres
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                // Row 3: quality filters
                HStack(spacing: 8) {
                    DecadeChip(selection: $selectedDecade)
                        .frame(maxWidth: .infinity)
                    RatingChip(minRating: $minRating)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct GenreChip: View {
    @Binding var selectedGenres: Set<String>
    let availableGenres: [String]

    private var label: String {
        switch selectedGenres.count {
        case 0: "Genre"
        case 1: selectedGenres.first ?? "Genre"
        default: "\(selectedGenres.count) Genres"
        }
    }

    var body: some View {
        Menu {
            if !selectedGenres.isEmpty {
                Button(role: .destructive) {
                    selectedGenres.removeAll()
                } label: {
                    Label("Clear Genres", systemImage: "xmark.circle")
                }
                Divider()
            }
            ForEach(availableGenres, id: \.self) { genre in
                Button {
                    if selectedGenres.contains(genre) {
                        selectedGenres.remove(genre)
                    } else {
                        selectedGenres.insert(genre)
                    }
                } label: {
                    if selectedGenres.contains(genre) {
                        Label(genre, systemImage: "checkmark")
                    } else {
                        Text(genre)
                    }
                }
            }
        } label: {
            Label(label, systemImage: "tag")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(!selectedGenres.isEmpty ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
    }
}
