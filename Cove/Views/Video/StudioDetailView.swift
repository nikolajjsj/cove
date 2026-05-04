import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// Displays movies or series matching a selected studio.
///
/// Uses a paged grid layout with sort options, following the same patterns
/// as `VideoGenreDetailView`.
struct StudioDetailView: View {
    let studioName: String
    let library: MediaLibrary?

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = PagedCollectionLoader<MediaItem>()

    // MARK: - Sort State

    @State private var sortField: SortField = .name
    @State private var sortOrder: Models.SortOrder = .ascending

    private let pageSize = 40

    @Default(.videoLibraryLayout) private var layoutMode

    /// Resolves the library — uses the explicitly provided one, or falls back
    /// to the first movies or TV shows library found in AppState.
    private var resolvedLibrary: MediaLibrary? {
        library
            ?? appState.libraries.first {
                $0.collectionType == .movies || $0.collectionType == .tvshows
            }
    }

    /// Determines the appropriate item types based on the library's collection type.
    private var studioItemTypes: [String] {
        switch resolvedLibrary?.collectionType {
        case .movies:
            return ["Movie"]
        case .tvshows:
            return ["Series"]
        default:
            return ["Movie", "Series"]
        }
    }

    private var sortOptions: SortOptions {
        SortOptions(field: sortField, order: sortOrder)
    }

    var body: some View {
        Group {
            StudioMainContent(loader: loader, itemNoun: itemNoun)
        }
        .navigationTitle(studioName)
        .largeNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    layoutMode == .grid ? "List" : "Grid",
                    systemImage: layoutMode == .grid ? "list.bullet" : "square.grid.2x2"
                ) {
                    layoutMode = layoutMode == .grid ? .list : .grid
                }
                StudioSortMenu(sortField: $sortField, sortOrder: $sortOrder)
            }
        }
        .task(id: studioName) { await loadFirstPage() }
        .onChange(of: sortField) { _, _ in reloadAfterSortChange() }
        .onChange(of: sortOrder) { _, _ in reloadAfterSortChange() }
    }

    // MARK: - Sort Change Reload

    private func reloadAfterSortChange() {
        loader.reset()
        Task { await loadFirstPage() }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library = resolvedLibrary else {
            loader.reset()
            return
        }

        let provider = authManager.provider
        let sort = sortOptions
        let itemTypes = studioItemTypes

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let filter = FilterOptions(
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: itemTypes,
                studios: [studioName],
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Helpers

    private var itemNoun: String {
        switch resolvedLibrary?.collectionType {
        case .movies:
            return loader.totalCount == 1 ? "movie" : "movies"
        case .tvshows:
            return loader.totalCount == 1 ? "show" : "shows"
        default:
            return loader.totalCount == 1 ? "item" : "items"
        }
    }
}

// MARK: - Sort Menu

private struct StudioSortMenu: View {
    @Binding var sortField: SortField
    @Binding var sortOrder: Models.SortOrder

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sortField) {
                Text("Name").tag(SortField.name)
                Text("Date Added").tag(SortField.dateAdded)
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
}

// MARK: - Main Content

private struct StudioMainContent: View {
    let loader: PagedCollectionLoader<MediaItem>
    let itemNoun: String

    var body: some View {
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
                systemImage: "film",
                description: Text("No movies or shows found for this studio.")
            )
        case .loaded:
            StudioScrollContent(loader: loader, itemNoun: itemNoun)
        }
    }
}

// MARK: - Scroll Content

private struct StudioScrollContent: View {
    let loader: PagedCollectionLoader<MediaItem>
    let itemNoun: String

    @Default(.gridDensity) private var gridDensity
    @Default(.videoLibraryLayout) private var layoutMode

    var body: some View {
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
                    StudioItemCountFooter(
                        totalCount: loader.totalCount, itemNoun: itemNoun)
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
                    StudioItemCountFooter(
                        totalCount: loader.totalCount, itemNoun: itemNoun
                    )
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

// MARK: - Item Count Footer

private struct StudioItemCountFooter: View {
    let totalCount: Int
    let itemNoun: String

    var body: some View {
        Text("\(totalCount) \(itemNoun)")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        StudioDetailView(
            studioName: "Universal Pictures",
            library: nil
        )
        .environment(state)
        .environment(state.authManager)
    }
}
