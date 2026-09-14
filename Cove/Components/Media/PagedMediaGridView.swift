import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// A generic paged grid view for browsing media items.
///
/// Consolidates the shared paged-grid pattern.
/// Each call-site provides only the item type, card builder, and display strings.
///
/// ```swift
/// PagedMediaGridView(
///     library: library,
///     itemType: "Movie",
///     sortField: sortField,
///     sortOrder: sortOrder,
///     isFavoriteFilter: isFavoriteFilter,
///     emptyTitle: "No Movies",
///     emptyIcon: "square.stack",
///     emptyMessage: "This library doesn't contain any movies yet.",
///     entityName: "album"
/// ) { item, imageURL in
///     MediaCard(item: item)
/// }
/// ```
struct PagedMediaGridView<Card: View>: View {
    let library: MediaLibrary?
    let itemType: String
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false
    let emptyTitle: String
    let emptyIcon: String
    let emptyMessage: String
    let entityName: String
    let imageSize: CGSize
    @ViewBuilder let card: (MediaItem, URL?) -> Card

    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState
    @State private var loader = PagedCollectionLoader<MediaItem>()

    private let pageSize = 40

    init(
        library: MediaLibrary?,
        itemType: String,
        sortField: SortField = .name,
        sortOrder: Models.SortOrder = .ascending,
        isFavoriteFilter: Bool = false,
        emptyTitle: String,
        emptyIcon: String,
        emptyMessage: String,
        entityName: String,
        imageSize: CGSize = ArtworkSize.poster,
        @ViewBuilder card: @escaping (MediaItem, URL?) -> Card
    ) {
        self.library = library
        self.itemType = itemType
        self.sortField = sortField
        self.sortOrder = sortOrder
        self.isFavoriteFilter = isFavoriteFilter
        self.emptyTitle = emptyTitle
        self.emptyIcon = emptyIcon
        self.emptyMessage = emptyMessage
        self.entityName = entityName
        self.imageSize = imageSize
        self.card = card
    }

    var body: some View {
        Group {
            PagedMediaGridContent(
                loader: loader,
                emptyTitle: emptyTitle,
                emptyIcon: emptyIcon,
                emptyMessage: emptyMessage,
                entityName: entityName,
                imageSize: imageSize,
                card: card
            )
        }
        .task(id: "\(library?.id.rawValue ?? "")-\(sortField)-\(sortOrder)-\(isFavoriteFilter)") {
            await loadFirstPage()
        }
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let favorite: Bool? = isFavoriteFilter ? true : nil
        let types = [itemType]
        let fetch = appState.pageFetcher(
            library: library, itemTypes: types,
            sort: SortOptions(field: sortField, order: sortOrder)
        ) { limit, startIndex in
            FilterOptions(
                isFavorite: favorite,
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: types
            )
        }
        await loader.loadFirstPage(pageSize: pageSize, fetch)
    }
}

// MARK: - Main Content

private struct PagedMediaGridContent<Card: View>: View {
    let loader: PagedCollectionLoader<MediaItem>
    let emptyTitle: String
    let emptyIcon: String
    let emptyMessage: String
    let entityName: String
    let imageSize: CGSize
    let card: (MediaItem, URL?) -> Card

    var body: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading \(entityName)s…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                emptyTitle.replacing("No ", with: "Unable to Load "),
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptyIcon,
                description: Text(emptyMessage)
            )
        case .loaded:
            PagedMediaGridScrollView(
                loader: loader,
                entityName: entityName,
                imageSize: imageSize,
                card: card
            )
        }
    }
}

// MARK: - Scroll View

private struct PagedMediaGridScrollView<Card: View>: View {
    let loader: PagedCollectionLoader<MediaItem>
    let entityName: String
    let imageSize: CGSize
    let card: (MediaItem, URL?) -> Card

    @Default(.gridDensity) private var gridDensity
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: gridDensity.columns,
                spacing: gridDensity.gridSpacing
            ) {
                ForEach(loader.items) { item in
                    card(item, imageURL(for: item))
                        .onAppear { loader.onItemAppeared(item) }
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
                Text(
                    "\(loader.totalCount) \(loader.totalCount == 1 ? entityName : entityName + "s")"
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
            }
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: imageSize
        )
    }
}
