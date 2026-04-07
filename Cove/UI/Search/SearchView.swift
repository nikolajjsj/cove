import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct SearchView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var searchText = ""
    @State private var results: SearchResults?
    @State private var isSearching = false
    @State private var recentSearches: [String] = []
    @State private var hasSearched = false

    /// How many items to preview per section before "See All".
    private var maxPreviewItems: Int {
        sizeClass == .compact ? 3 : 5
    }

    private static let recentSearchesKey = "recentSearches"

    var body: some View {
        Group {
            if searchText.count < 2 {
                idleContent
            } else if isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let results, hasSearched {
                if results.items.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    resultsContent(results)
                }
            } else {
                idleContent
            }
        }
        .searchable(text: $searchText, prompt: "Movies, shows, music…")
        .task(id: searchText) {
            await performSearch()
        }
        .onAppear {
            loadRecentSearches()
        }
    }

    // MARK: - Idle Content (Recent Searches)

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
                            Button("Clear") {
                                recentSearches = []
                                saveRecentSearches()
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

    // MARK: - Results Content

    private func resultsContent(_ results: SearchResults) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
            }
            .padding(.vertical)
        }
    }

    // MARK: - Search Logic

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)

        guard query.count >= 2 else {
            results = nil
            hasSearched = false
            return
        }

        isSearching = true
        defer { isSearching = false }

        // Debounce
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return  // Cancelled — user typed more
        }

        do {
            let searchResults = try await authManager.provider.search(
                query: query,
                mediaTypes: [.movie, .series, .artist, .album]
            )
            results = searchResults
            hasSearched = true

            if !searchResults.items.isEmpty {
                addToRecentSearches(query)
            }
        } catch {
            if !Task.isCancelled {
                results = SearchResults()
                hasSearched = true
            }
        }
    }

    // MARK: - Recent Searches Persistence

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
