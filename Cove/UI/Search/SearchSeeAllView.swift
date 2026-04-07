import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct SearchSeeAllView: View {
    let query: String
    let mediaType: MediaType
    let title: String

    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalCount = 0
    @State private var hasMore = false
    @State private var errorMessage: String?

    private let pageSize = 40

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
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No \(title.lowercased()) found for \"\(query)\".")
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            SearchResultRow(item: item)
                        }
                        .onAppear { onItemAppeared(item) }
                    }

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }

                    if !items.isEmpty && !hasMore && totalCount > 0 {
                        Text("\(totalCount) \(totalCount == 1 ? "result" : "results")")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("\(title) — \"\(query)\"")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFirstPage() }
    }

    // MARK: - Pagination

    private func onItemAppeared(_ item: MediaItem) {
        guard hasMore, !isLoadingMore else { return }
        let thresholdIndex = max(items.count - 10, 0)
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            index >= thresholdIndex
        else { return }
        Task { await loadNextPage() }
    }

    private func loadFirstPage() async {
        isLoading = true
        errorMessage = nil
        items = []

        do {
            let result = try await authManager.provider.searchPaged(
                query: query,
                includeItemTypes: includeItemTypes,
                limit: pageSize,
                startIndex: 0
            )
            items = result.items
            totalCount = result.totalCount
            hasMore = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let result = try await authManager.provider.searchPaged(
                query: query,
                includeItemTypes: includeItemTypes,
                limit: pageSize,
                startIndex: items.count
            )
            let existingIDs = Set(items.map(\.id))
            let newItems = result.items.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: newItems)
            totalCount = result.totalCount
            hasMore = result.hasMore
        } catch {
            hasMore = false
        }

        isLoadingMore = false
    }

    // MARK: - Helpers

    /// Maps our MediaType to Jellyfin's IncludeItemTypes strings.
    private var includeItemTypes: [String]? {
        switch mediaType {
        case .movie: ["Movie"]
        case .series: ["Series"]
        case .album: ["MusicAlbum"]
        case .artist: ["MusicArtist"]
        case .episode: ["Episode"]
        case .track: ["Audio"]
        default: nil
        }
    }
}
