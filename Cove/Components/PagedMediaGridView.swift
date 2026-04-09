import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// A generic paged grid view for browsing media items.
///
/// Consolidates the shared pattern from `AlbumListView` and `ArtistListView`.
/// Each call-site provides only the item type, card builder, and display strings.
///
/// ```swift
/// PagedMediaGridView(
///     library: library,
///     itemType: "MusicAlbum",
///     sortField: sortField,
///     sortOrder: sortOrder,
///     isFavoriteFilter: isFavoriteFilter,
///     emptyTitle: "No Albums",
///     emptyIcon: "square.stack",
///     emptyMessage: "Your music library doesn't contain any albums yet.",
///     entityName: "album"
/// ) { item, imageURL in
///     AlbumCard(item: item, imageURL: imageURL)
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
        imageSize: CGSize = CGSize(width: 300, height: 300),
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
            mainContent
        }
        .task(id: "\(library?.id.rawValue ?? "")-\(sortField)-\(sortOrder)-\(isFavoriteFilter)") {
            await loadFirstPage()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading \(entityName)s…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                emptyTitle.replacingOccurrences(of: "No ", with: "Unable to Load "),
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
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)],
                spacing: 20
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

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = authManager.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: sortField, order: sortOrder)
            let filter = FilterOptions(
                isFavorite: isFavoriteFilter ? true : Optional<Bool>.none,
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: [itemType]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: imageSize
        )
    }
}
