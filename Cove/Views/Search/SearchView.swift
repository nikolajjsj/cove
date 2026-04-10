import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

// MARK: - Search Scope

enum SearchScope: String, CaseIterable {
    case all
    case video
    case music

    var label: String {
        switch self {
        case .all: "All"
        case .video: "Video"
        case .music: "Music"
        }
    }

    var mediaTypes: [MediaType] {
        switch self {
        case .all: [.movie, .series, .episode, .artist, .album, .track]
        case .video: [.movie, .series, .episode]
        case .music: [.artist, .album, .track]
        }
    }
}

// MARK: - Search View

struct SearchView: View {
    @State private var searchText = ""
    @State private var scope: SearchScope = .all
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
            scope: scope,
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
        // Scope picker appears below the search bar while searching.
        .searchable(text: $searchText, prompt: "Movies, shows, music…")
        .searchScopes($scope) {
            ForEach(SearchScope.allCases, id: \.self) { s in
                Text(s.label).tag(s)
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
    let scope: SearchScope
    @Binding var watchedFilter: WatchedFilter
    @Binding var favoriteOnly: Bool
    @Binding var selectedDecade: Decade?
    @Binding var minRating: Double?
    let recentSearches: [String]
    let onSearch: (String) -> Void
    let onSelectRecent: (String) -> Void
    let onClearRecents: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isSearching) private var isSearching

    @State private var results: SearchResults?
    @State private var isLoading = false

    // MARK: Derived

    private var maxPreviewItems: Int { sizeClass == .compact ? 3 : 5 }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var isQueryLongEnough: Bool { trimmedQuery.count >= 2 }

    private var hasActiveFilters: Bool {
        watchedFilter != .all || favoriteOnly || selectedDecade != nil || minRating != nil
    }

    /// Scope filtering is done client-side so switching between All/Video/Music
    /// is instant with no extra network request.
    private var scopedResults: SearchResults? {
        guard let results else { return nil }
        guard scope != .all else { return results }
        return SearchResults(
            items: results.items.filter { scope.mediaTypes.contains($0.mediaType) }
        )
    }

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
            // Filter chips slide in from the top when the search bar is focused.
            if isSearching {
                SearchFilterBar(
                    watchedFilter: $watchedFilter,
                    favoriteOnly: $favoriteOnly,
                    selectedDecade: $selectedDecade,
                    minRating: $minRating
                )
                .padding(.horizontal)
                .padding(.vertical, 10)
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
            contentArea
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

    // MARK: Content Area

    @ViewBuilder
    private var contentArea: some View {
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
        } else if let scoped = scopedResults {
            if scoped.items.isEmpty {
                SearchEmptyState(query: trimmedQuery, hasActiveFilters: hasActiveFilters)
                    .transition(.opacity)
            } else {
                SearchResultsScrollView(
                    results: scoped,
                    query: trimmedQuery,
                    maxPreviewItems: maxPreviewItems
                )
                .transition(.opacity)
            }
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
            // Always fetch all types; scope filtering is client-side.
            let fetched = try await authManager.provider.filteredSearch(
                query: trimmedQuery,
                isFavorite: favoriteOnly ? true : nil,
                isPlayed: {
                    switch watchedFilter {
                    case .all: return nil
                    case .watched: return true
                    case .unwatched: return false
                    }
                }(),
                years: selectedDecade?.years,
                minCommunityRating: minRating
            )
            results = fetched
            if !fetched.items.isEmpty { onSearch(trimmedQuery) }
        } catch {
            if !Task.isCancelled { results = SearchResults() }
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
            SearchHero()
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

// MARK: - Search Hero

private struct SearchHero: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Soft gradient halo behind the icon.
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.18), .purple.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 112)
                    .blur(radius: 4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.12), .purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("Search Your Library")
                    .font(.title2)
                    .bold()

                Text("Movies, shows, artists, albums, and more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
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

// MARK: - Filter Bar

/// Two rows of equal-width chips shown while the search bar is focused.
/// Appears with a spring push-from-top transition.
private struct SearchFilterBar: View {
    @Binding var watchedFilter: WatchedFilter
    @Binding var favoriteOnly: Bool
    @Binding var selectedDecade: Decade?
    @Binding var minRating: Double?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WatchedFilterChip(selection: $watchedFilter)
                    .frame(maxWidth: .infinity)
                FavoriteChip(isOn: $favoriteOnly)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                DecadeChip(selection: $selectedDecade)
                    .frame(maxWidth: .infinity)
                RatingChip(minRating: $minRating)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Empty State

private struct SearchEmptyState: View {
    let query: String
    let hasActiveFilters: Bool

    var body: some View {
        if hasActiveFilters {
            ContentUnavailableView(
                "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(
                    "No items match '\(query)' with the current filters. Try removing some filters."
                )
            )
        } else {
            ContentUnavailableView.search(text: query)
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
