import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import Persistence
import SwiftUI

// MARK: - Search View

struct SearchView: View {
    @State private var searchText = ""
    @State private var watchedFilter: WatchedFilter = .all
    @State private var favoriteOnly = false
    @State private var selectedDecade: Decade? = nil
    @State private var minRating: Double? = nil
    @State private var recentSearches: [String] = []

    private static let recentSearchesKey = "recentSearches"

    var body: some View {
        // SearchContentView is a separate struct so @Environment(\.isSearching)
        // is correctly injected — it only works in descendants of the view
        // that applies .searchable, not on the view itself.
        SearchContentView(
            searchText: $searchText,
            watchedFilter: $watchedFilter,
            favoriteOnly: $favoriteOnly,
            selectedDecade: $selectedDecade,
            minRating: $minRating,
            recentSearches: recentSearches,
            onSearch: addToRecentSearches,
            onSelectRecent: { searchText = $0 },
            onClearRecents: {
                recentSearches = []
                saveRecentSearches()
            }
        )
        .searchable(text: $searchText, prompt: "Movies, shows, music…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                MediaFilterMenu(
                    selection: MediaFilterSelection(
                        watched: $watchedFilter,
                        favoritesOnly: $favoriteOnly,
                        decade: $selectedDecade,
                        minRating: $minRating
                    )
                )
            }
        }
        .onAppear {
            loadRecentSearches()
        }
    }

    // MARK: - Persistence

    private func loadRecentSearches() {
        recentSearches =
            UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
    }

    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    private func addToRecentSearches(_ query: String) {
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(10))
        saveRecentSearches()
    }
}

// MARK: - Content View

/// Owns all search state and reacts to search bar focus.
///
/// Must be a child of the `.searchable` view so `@Environment(\.isSearching)`
/// resolves correctly.
private struct SearchContentView: View {
    @Binding var searchText: String
    @Binding var watchedFilter: WatchedFilter
    @Binding var favoriteOnly: Bool
    @Binding var selectedDecade: Decade?
    @Binding var minRating: Double?
    let recentSearches: [String]
    let onSearch: (String) -> Void
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isSearching) private var isSearching

    @State private var results: SearchResults?
    @State private var isLoading = false

    // MARK: Derived

    private static let musicTypes: Set<MediaType> = [.artist, .album, .track]

    private var maxPreviewItems: Int { sizeClass == .compact ? 3 : 5 }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var isQueryLongEnough: Bool { trimmedQuery.count >= 2 }

    /// Bundles the filter bindings for the menu and the active-filter row.
    ///
    /// Search has no library context, so genre is unavailable here.
    private var filterSelection: MediaFilterSelection {
        MediaFilterSelection(
            watched: $watchedFilter,
            favoritesOnly: $favoriteOnly,
            decade: $selectedDecade,
            minRating: $minRating
        )
    }

    private var hasActiveFilters: Bool { filterSelection.isActive }

    private var searchTaskKey: SearchKey {
        SearchKey(
            query: searchText,
            watchedFilter: watchedFilter,
            favoriteOnly: favoriteOnly,
            selectedDecade: selectedDecade,
            minRating: minRating
        )
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Applied filters slide in from the top; nothing is shown until the
            // user has actually narrowed the search.
            if isSearching && hasActiveFilters {
                ActiveFilterBar(selection: filterSelection)
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity),
                            removal: .push(from: .bottom).combined(with: .opacity)
                        )
                    )

                Divider()
                    .transition(.opacity)
            }

            // Content area — crossfades between all states.
            SearchContentArea(
                isQueryLongEnough: isQueryLongEnough,
                isLoading: isLoading,
                results: results,
                hasActiveFilters: hasActiveFilters,
                trimmedQuery: trimmedQuery,
                maxPreviewItems: maxPreviewItems,
                recentSearches: recentSearches,
                onSelectRecent: onSelectRecent,
                onClearRecents: onClearRecents
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Spring drives the chip bar; easeInOut drives content-level transitions.
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSearching)
        .animation(.easeInOut(duration: 0.22), value: isQueryLongEnough)
        .animation(.easeInOut(duration: 0.18), value: isLoading)
        .task(id: searchTaskKey) {
            await performSearch()
        }
    }

    // MARK: Search Logic

    private func performSearch() async {
        guard isQueryLongEnough else {
            results = nil
            return
        }

        // Debounce — cancelled automatically if searchTaskKey changes.
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        // Only show the spinner after the debounce window to avoid
        // flickering on every keystroke.
        isLoading = true
        defer { isLoading = false }

        do {
            let isPlayed: Bool? = {
                switch watchedFilter {
                case .all: return nil
                case .watched: return true
                case .unwatched: return false
                }
            }()
            let fetched: SearchResults
            if let local = await appState.localCatalog() {
                // Instant and offline. Diverges from the server's fuzzy matching
                // by design — see the spec's open decisions.
                let items = try await local.repository.search(
                    term: trimmedQuery,
                    filter: FilterOptions(
                        years: selectedDecade?.years,
                        isFavorite: favoriteOnly ? true : nil,
                        isPlayed: isPlayed,
                        limit: 60, startIndex: 0,
                        minCommunityRating: minRating),
                    scope: local.scope)
                fetched = SearchResults(items: items)
            } else {
                // Always fetch all types; scope filtering is client-side.
                fetched = try await authManager.provider.filteredSearch(
                    query: trimmedQuery,
                    isFavorite: favoriteOnly ? true : nil,
                    isPlayed: isPlayed,
                    years: selectedDecade?.years,
                    minCommunityRating: minRating
                )
            }
            // Search hits the server directly rather than going through the
            // library list, so it needs its own guard.
            let visible = FeatureFlags.musicEnabled
                ? fetched
                : SearchResults(
                    items: fetched.items.filter { !Self.musicTypes.contains($0.mediaType) }
                )
            results = visible
            if !visible.items.isEmpty { onSearch(trimmedQuery) }
        } catch {
            if !Task.isCancelled { results = SearchResults() }
        }
    }
}

// MARK: - Content Area

/// Crossfades between discovery, loading, empty, and results states.
private struct SearchContentArea: View {
    let isQueryLongEnough: Bool
    let isLoading: Bool
    let results: SearchResults?
    let hasActiveFilters: Bool
    let trimmedQuery: String
    let maxPreviewItems: Int
    let recentSearches: [String]
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        if !isQueryLongEnough {
            // Show the discovery view whether or not the bar is focused.
            // Tapping the bar does NOT cause a jarring state switch —
            // the chips just slide in above the same content.
            SearchDiscoveryView(
                recentSearches: recentSearches,
                onSelectRecent: onSelectRecent,
                onClearRecents: onClearRecents
            )
            .transition(.opacity)
        } else if isLoading {
            ProgressView()
                .transition(.opacity)
        } else if let results {
            if results.items.isEmpty {
                Group {
                    if hasActiveFilters {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(
                                "No items match '\(trimmedQuery)' with the current filters. Try removing some filters."
                            )
                        )
                    } else {
                        ContentUnavailableView.search(text: trimmedQuery)
                    }
                }
                .transition(.opacity)
            } else {
                SearchResultsScrollView(
                    results: results,
                    query: trimmedQuery,
                    maxPreviewItems: maxPreviewItems
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Discovery View

/// Shown while the search bar is idle or has fewer than 2 characters.
/// Recent searches appear as tappable capsule chips in a wrapping flow layout.
private struct SearchDiscoveryView: View {
    let recentSearches: [String]
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        if recentSearches.isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Movies, shows, artists, albums, and more.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                RecentSearchesSection(
                    recentSearches: recentSearches,
                    onSelect: onSelectRecent,
                    onClear: onClearRecents
                )
                .padding()
            }
        }
    }
}

// MARK: - Recent Searches Section

private struct RecentSearchesSection: View {
    let recentSearches: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                Button("Clear All", role: .destructive, action: onClear)
                    .font(.subheadline)
            }

            // Wrapping chip layout — more visually engaging than a plain list.
            FlowLayout(spacing: 8) {
                ForEach(recentSearches, id: \.self) { query in
                    RecentSearchChip(query: query, onSelect: onSelect)
                }
            }
        }
    }
}

private struct RecentSearchChip: View {
    let query: String
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(query)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(query)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Results Scroll View

private struct SearchResultsScrollView: View {
    let results: SearchResults
    let query: String
    let maxPreviewItems: Int

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // SearchResultsSection self-hides when its items array is empty,
                // so all types are passed unconditionally.
                SearchResultsSection(
                    title: "Movies",
                    items: results.items(ofType: .movie),
                    mediaType: .movie,
                    query: query,
                    maxItems: maxPreviewItems
                )
                SearchResultsSection(
                    title: "TV Shows",
                    items: results.items(ofType: .series),
                    mediaType: .series,
                    query: query,
                    maxItems: maxPreviewItems
                )
                SearchResultsSection(
                    title: "Episodes",
                    items: results.items(ofType: .episode),
                    mediaType: .episode,
                    query: query,
                    maxItems: maxPreviewItems
                )
                SearchResultsSection(
                    title: "Artists",
                    items: results.items(ofType: .artist),
                    mediaType: .artist,
                    query: query,
                    maxItems: maxPreviewItems
                )
                SearchResultsSection(
                    title: "Albums",
                    items: results.items(ofType: .album),
                    mediaType: .album,
                    query: query,
                    maxItems: maxPreviewItems
                )
                SearchResultsSection(
                    title: "Songs",
                    items: results.items(ofType: .track),
                    mediaType: .track,
                    query: query,
                    maxItems: maxPreviewItems
                )
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Search Task Key

/// Bundles every piece of state that should trigger a new search.
/// When any field changes, `task(id: searchTaskKey)` cancels the in-flight
/// request and starts a fresh one with the updated parameters.
private struct SearchKey: Equatable {
    let query: String
    let watchedFilter: WatchedFilter
    let favoriteOnly: Bool
    let selectedDecade: Decade?
    let minRating: Double?
}
