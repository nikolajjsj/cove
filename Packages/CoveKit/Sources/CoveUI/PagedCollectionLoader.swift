import Foundation
import Observation

/// An `@Observable` model that manages paginated collection fetching with
/// infinite-scroll support.
///
/// This is the paginated counterpart to ``CollectionLoader``. It handles
/// first-page loading, incremental next-page fetching, deduplication, and
/// provides an `onItemAppeared` helper that views can call from `.onAppear`
/// to trigger automatic prefetching.
///
/// ```swift
/// @State private var loader = PagedCollectionLoader<MediaItem>()
///
/// // In body – switch on loader.phase for initial state:
/// ScrollView {
///     LazyVGrid(columns: columns) {
///         ForEach(loader.items) { item in
///             ItemCard(item: item)
///                 .onAppear { loader.onItemAppeared(item) }
///         }
///     }
///
///     if loader.isLoadingMore {
///         ProgressView()
///     }
/// }
/// .task {
///     await loader.loadFirstPage { limit, startIndex in
///         let result = try await provider.pagedItems(
///             in: library,
///             sort: sort,
///             filter: FilterOptions(limit: limit, startIndex: startIndex)
///         )
///         return .init(items: result.items, totalCount: result.totalCount)
///     }
/// }
/// ```
@MainActor
@Observable
public final class PagedCollectionLoader<Element: Sendable & Identifiable>
where Element.ID: Hashable {

    // MARK: - Page Result

    /// A lightweight page result returned by the fetch closure.
    ///
    /// This avoids coupling CoveUI to any particular `PagedResult` type
    /// from the Models layer. Call-sites map their concrete result type
    /// into this at the boundary:
    ///
    /// ```swift
    /// let result = try await provider.pagedItems(...)
    /// return .init(items: result.items, totalCount: result.totalCount)
    /// ```
    public struct Page: Sendable {
        public let items: [Element]
        public let totalCount: Int

        public init(items: [Element], totalCount: Int) {
            self.items = items
            self.totalCount = totalCount
        }
    }

    /// The closure signature used to fetch a page of items.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of items to return.
    ///   - startIndex: The 0-based index of the first item to return.
    /// - Returns: A ``Page`` containing the items and server-side total count.
    public typealias PageFetcher =
        @Sendable (
            _ limit: Int, _ startIndex: Int
        ) async throws -> Page

    // MARK: - Phase

    /// The discrete states of the initial page load.
    ///
    /// Subsequent page loads (infinite scroll) do **not** change the phase —
    /// they flip ``isLoadingMore`` instead, so existing content stays visible.
    public enum Phase: Sendable {
        /// The first page is being fetched (also the initial state).
        case loading
        /// The first page fetch failed.
        case failed(String)
        /// The first page returned zero items.
        case empty
        /// At least one item has been loaded.
        case loaded
    }

    // MARK: - Published State

    /// The current phase of the *initial* load.
    public private(set) var phase: Phase = .loading

    /// All items accumulated across pages.
    public private(set) var items: [Element] = []

    /// The server-reported total item count for the current query.
    public private(set) var totalCount: Int = 0

    /// Whether there are more pages available.
    public private(set) var hasMore: Bool = false

    /// Whether a subsequent (non-first) page is currently being fetched.
    public private(set) var isLoadingMore: Bool = false

    // MARK: - Private

    /// The stored fetch closure, set on first load and reused for subsequent pages.
    private var pageFetcher: PageFetcher?

    /// Items per page.
    private var pageSize: Int = 40

    // MARK: - Init

    /// Creates a loader in the `.loading` phase.
    ///
    /// Marked `nonisolated` so `@State` can call it from a nonisolated `View.init`.
    nonisolated public init() {}

    // MARK: - Actions

    /// Fetches the first page, replacing any previously loaded items.
    ///
    /// The fetch closure is stored internally so that ``loadNextPage()`` and
    /// ``onItemAppeared(_:prefetchThreshold:)`` can reuse it without the
    /// caller having to pass it again.
    ///
    /// - Parameters:
    ///   - pageSize: Number of items per page. Defaults to `40`.
    ///   - fetch: A sendable closure that fetches a single page given
    ///     `(limit, startIndex)` parameters.
    public func loadFirstPage(
        pageSize: Int = 40,
        _ fetch: @escaping PageFetcher
    ) async {
        self.pageFetcher = fetch
        self.pageSize = pageSize
        phase = .loading
        items = []
        totalCount = 0
        hasMore = false

        do {
            let result = try await fetch(pageSize, 0)
            guard !Task.isCancelled else { return }
            items = result.items
            totalCount = result.totalCount
            hasMore = result.items.count < result.totalCount
            phase = result.items.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fetches the next page and appends new items, deduplicating by ID.
    ///
    /// Safe to call multiple times — it no-ops if a page fetch is already
    /// in-flight or there are no more pages.
    public func loadNextPage() async {
        guard let fetch = pageFetcher, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetch(pageSize, items.count)
            guard !Task.isCancelled else { return }

            // Deduplicate in case the server shifted items between pages.
            let existingIDs = Set(items.map(\.id))
            let newItems = result.items.filter { !existingIDs.contains($0.id) }

            items.append(contentsOf: newItems)
            totalCount = result.totalCount
            hasMore = items.count < result.totalCount
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // On pagination failure, stop paging — don't clear existing items.
            hasMore = false
        }
    }

    /// Call this from each item's `.onAppear` to trigger automatic prefetching
    /// when the user scrolls near the end of the list.
    ///
    /// - Parameters:
    ///   - item: The item that just appeared on screen.
    ///   - prefetchThreshold: How many items from the end should trigger a
    ///     prefetch. Defaults to `10`.
    public func onItemAppeared(
        _ item: Element,
        prefetchThreshold: Int = 10
    ) {
        guard hasMore, !isLoadingMore else { return }
        let thresholdIndex = max(items.count - prefetchThreshold, 0)
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            index >= thresholdIndex
        else { return }
        Task { await loadNextPage() }
    }

    /// Resets the loader to its initial `.loading` state, clearing all items
    /// and the stored fetch closure.
    public func reset() {
        phase = .loading
        items = []
        totalCount = 0
        hasMore = false
        isLoadingMore = false
        pageFetcher = nil
    }
}
