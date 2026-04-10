import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

// MARK: - Filter Enums (file-level so LibraryFilterSheet can access them)

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

private enum Decade: String, CaseIterable, Equatable {
    case twenties = "2020s"
    case tens = "2010s"
    case noughties = "2000s"
    case nineties = "1990s"
    case eighties = "1980s"

    var years: [Int] {
        switch self {
        case .twenties: return Array(2020...2029)
        case .tens: return Array(2010...2019)
        case .noughties: return Array(2000...2009)
        case .nineties: return Array(1990...1999)
        case .eighties: return Array(1980...1989)
        }
    }
}

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

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

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
            FilterChipBar(
                watchedFilter: $watchedFilter,
                favoriteOnly: $favoriteOnly,
                selectedGenres: $selectedGenres,
                selectedDecade: $selectedDecade,
                minRating: $minRating,
                isVideoLibrary: isVideoLibrary,
                availableGenres: availableGenres
            )
            .padding(.bottom, 8)
            .padding(.horizontal)

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
            HStack(spacing: 8) {
                WatchedFilterChip(selection: $watchedFilter)
                    .frame(maxWidth: .infinity)
                FavoriteChip(isOn: $favoriteOnly)
                    .frame(maxWidth: .infinity)
            }
            if isVideoLibrary {
                HStack(spacing: 8) {
                    if !availableGenres.isEmpty {
                        GenreChip(selectedGenres: $selectedGenres, availableGenres: availableGenres)
                            .frame(maxWidth: .infinity)
                    }
                    DecadeChip(selection: $selectedDecade)
                        .frame(maxWidth: .infinity)
                    RatingChip(minRating: $minRating)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Individual Chips

private struct WatchedFilterChip: View {
    @Binding var selection: WatchedFilter

    var body: some View {
        Menu {
            Picker("Status", selection: $selection) {
                ForEach(WatchedFilter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.systemImage).tag(filter)
                }
            }
        } label: {
            Label(
                selection == .all ? "Watched" : selection.label,
                systemImage: selection.systemImage
            )
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selection != .all ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
    }
}

private struct FavoriteChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label("Favorites", systemImage: isOn ? "heart.fill" : "heart")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .pink : .secondary)
        .buttonBorderShape(.capsule)
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

private struct DecadeChip: View {
    @Binding var selection: Decade?

    var body: some View {
        Menu {
            Picker("Year", selection: $selection) {
                Text("Any Year").tag(Decade?.none)
                ForEach(Decade.allCases, id: \.self) { decade in
                    Text(decade.rawValue).tag(Decade?.some(decade))
                }
            }
        } label: {
            Label(selection?.rawValue ?? "Year", systemImage: "calendar")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selection != nil ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
    }
}

private struct RatingChip: View {
    @Binding var minRating: Double?

    private var label: String {
        minRating.map { "\(Int($0))+ ★" } ?? "Rating"
    }

    var body: some View {
        Menu {
            Picker("Min Rating", selection: $minRating) {
                Text("Any Rating").tag(Double?.none)
                Text("6+ ★").tag(Double?.some(6))
                Text("7+ ★").tag(Double?.some(7))
                Text("8+ ★").tag(Double?.some(8))
                Text("9+ ★").tag(Double?.some(9))
            }
        } label: {
            Label(label, systemImage: minRating != nil ? "star.fill" : "star")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(minRating != nil ? .yellow : .secondary)
        .buttonBorderShape(.capsule)
    }
}
