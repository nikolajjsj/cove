import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

// MARK: - Search Scope

private enum SearchScope: String, CaseIterable {
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
    @State private var recentSearches: [String] = []

    private static let recentSearchesKey = "recentSearches"

    var body: some View {
        // SearchResultsView is a separate struct so it can read
        // @Environment(\.isSearching), which is only injected into
        // descendants of the view that owns .searchable.
        SearchResultsView(
            searchText: $searchText,
            scope: scope,
            recentSearches: recentSearches,
            onSearch: addToRecentSearches,
            onClearRecentSearches: {
                recentSearches = []
                saveRecentSearches()
            }
        )
        .searchable(text: $searchText, prompt: "Movies, shows, music…")
        .searchScopes($scope) {
            ForEach(SearchScope.allCases, id: \.self) { s in
                Text(s.label).tag(s)
            }
        }
        .searchSuggestions {
            ForEach(recentSearches, id: \.self) { query in
                Label(query, systemImage: "clock")
                    .searchCompletion(query)
            }
        }
        .onAppear {
            loadRecentSearches()
        }
    }

    // MARK: - Recent Searches

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
    }

    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    private func addToRecentSearches(_ query: String) {
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        recentSearches.insert(query, at: 0)
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        saveRecentSearches()
    }
}

// MARK: - Search Results View

/// Owns the search logic and reacts to search bar focus state.
///
/// Kept separate from `SearchView` because `@Environment(\.isSearching)` is
/// only available in descendants of the view that applies `.searchable`.
private struct SearchResultsView: View {
    @Binding var searchText: String
    let scope: SearchScope
    let recentSearches: [String]
    let onSearch: (String) -> Void
    let onClearRecentSearches: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isSearching) private var isSearching

    @State private var results: SearchResults?
    @State private var isLoading = false

    private var maxPreviewItems: Int { sizeClass == .compact ? 3 : 5 }

    /// Results filtered to the current scope — client-side, no extra request.
    private var scopedResults: SearchResults? {
        guard let results else { return nil }
        guard scope != .all else { return results }
        return SearchResults(
            items: results.items.filter { scope.mediaTypes.contains($0.mediaType) })
    }

    var body: some View {
        Group {
            if !isSearching {
                idleContent
            } else if searchText.trimmingCharacters(in: .whitespaces).count < 2 {
                // Bar is focused but the query is too short — the system
                // .searchSuggestions strip handles the recent-searches UX here.
                Color.clear
            } else if isLoading {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let results = scopedResults {
                if results.items.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    resultsContent(results)
                }
            } else {
                Color.clear
            }
        }
        .task(id: searchText) {
            await performSearch()
        }
    }

    // MARK: - Idle State

    private var idleContent: some View {
        Group {
            if recentSearches.isEmpty {
                ContentUnavailableView(
                    "Search Your Library",
                    systemImage: "magnifyingglass",
                    description: Text("Find movies, shows, artists, and albums.")
                )
            } else {
                List {
                    Section {
                        ForEach(recentSearches, id: \.self) { query in
                            Button {
                                searchText = query
                            } label: {
                                Label(query, systemImage: "clock")
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Recent Searches")
                            Spacer()
                            Button("Clear", role: .destructive) {
                                onClearRecentSearches()
                            }
                            .font(.subheadline)
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Results

    private func resultsContent(_ results: SearchResults) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Scope filtering is already applied via scopedResults.
                // SearchResultsSection renders nothing when its items array is
                // empty, so we can pass all types and let sections self-hide.
                SearchResultsSection(
                    title: "Movies",
                    items: results.items(ofType: .movie),
                    mediaType: .movie,
                    query: searchText,
                    maxItems: maxPreviewItems
                )

                SearchResultsSection(
                    title: "TV Shows",
                    items: results.items(ofType: .series),
                    mediaType: .series,
                    query: searchText,
                    maxItems: maxPreviewItems
                )

                SearchResultsSection(
                    title: "Episodes",
                    items: results.items(ofType: .episode),
                    mediaType: .episode,
                    query: searchText,
                    maxItems: maxPreviewItems
                )

                SearchResultsSection(
                    title: "Artists",
                    items: results.items(ofType: .artist),
                    mediaType: .artist,
                    query: searchText,
                    maxItems: maxPreviewItems
                )

                SearchResultsSection(
                    title: "Albums",
                    items: results.items(ofType: .album),
                    mediaType: .album,
                    query: searchText,
                    maxItems: maxPreviewItems
                )

                SearchResultsSection(
                    title: "Songs",
                    items: results.items(ofType: .track),
                    mediaType: .track,
                    query: searchText,
                    maxItems: maxPreviewItems
                )
            }
            .padding(.vertical)
        }
    }

    // MARK: - Search

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)

        guard query.count >= 2 else {
            results = nil
            return
        }

        // Debounce — if searchText changes, task(id: searchText) cancels this.
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        // Show spinner only after the debounce window, not on every keystroke.
        isLoading = true
        defer { isLoading = false }

        do {
            // Always request all types from the server. Scope filtering is done
            // client-side on scopedResults so switching scope is instant.
            let searchResults = try await authManager.provider.search(
                query: query,
                mediaTypes: [.movie, .series, .episode, .artist, .album, .track]
            )
            results = searchResults
            if !searchResults.items.isEmpty {
                onSearch(query)
            }
        } catch {
            if !Task.isCancelled {
                results = SearchResults()
            }
        }
    }
}
