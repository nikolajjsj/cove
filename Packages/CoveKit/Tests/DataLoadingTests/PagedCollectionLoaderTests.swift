import Foundation
import Testing

@testable import DataLoading

@Suite("PagedCollectionLoader")
struct PagedCollectionLoaderTests {

    // MARK: - Test Helpers

    /// A trivial Identifiable + Sendable element for testing.
    struct Item: Sendable, Identifiable, Equatable {
        let id: Int
        let name: String

        init(id: Int, name: String = "") {
            self.id = id
            self.name = name
        }
    }

    enum TestError: Error, LocalizedError {
        case simulated

        var errorDescription: String? { "simulated" }
    }

    /// Creates a page fetcher that returns items from a fixed pool.
    /// Simulates server-side pagination with a known total count.
    static func makeFetcher(
        totalItems: Int,
        namePrefix: String = "Item"
    ) -> PagedCollectionLoader<Item>.PageFetcher {
        { limit, startIndex in
            let endIndex = min(startIndex + limit, totalItems)
            let items = (startIndex..<endIndex).map { Item(id: $0, name: "\(namePrefix) \($0)") }
            return .init(items: items, totalCount: totalItems)
        }
    }

    // MARK: - Initial State

    @Test @MainActor
    func initialPhaseIsLoading() {
        let loader = PagedCollectionLoader<Item>()
        guard case .loading = loader.phase else {
            Issue.record("Expected .loading, got \(loader.phase)")
            return
        }
        #expect(loader.items.isEmpty)
        #expect(loader.totalCount == 0)
        #expect(!loader.hasMore)
        #expect(!loader.isLoadingMore)
    }

    // MARK: - First Page Loading

    @Test @MainActor
    func loadFirstPageTransitionsToLoaded() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 25))

        guard case .loaded = loader.phase else {
            Issue.record("Expected .loaded, got \(loader.phase)")
            return
        }
        #expect(loader.items.count == 10)
        #expect(loader.totalCount == 25)
        #expect(loader.hasMore)
    }

    @Test @MainActor
    func loadFirstPageTransitionsToEmptyWhenNoItems() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 0))

        guard case .empty = loader.phase else {
            Issue.record("Expected .empty, got \(loader.phase)")
            return
        }
        #expect(loader.items.isEmpty)
        #expect(loader.totalCount == 0)
        #expect(!loader.hasMore)
    }

    @Test @MainActor
    func loadFirstPageTransitionsToFailedOnError() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10) { _, _ in
            throw TestError.simulated
        }

        guard case .failed(let message) = loader.phase else {
            Issue.record("Expected .failed, got \(loader.phase)")
            return
        }
        #expect(message.contains("simulated") || !message.isEmpty)
        #expect(loader.items.isEmpty)
    }

    @Test @MainActor
    func loadFirstPageWithFewerItemsThanPageSizeSetsHasMoreFalse() async {
        let loader = PagedCollectionLoader<Item>()

        // Total is 5, page size is 10 — all items fit in first page
        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 5))

        guard case .loaded = loader.phase else {
            Issue.record("Expected .loaded, got \(loader.phase)")
            return
        }
        #expect(loader.items.count == 5)
        #expect(loader.totalCount == 5)
        #expect(!loader.hasMore)
    }

    @Test @MainActor
    func loadFirstPageWithExactPageSizeCountSetsHasMoreFalse() async {
        let loader = PagedCollectionLoader<Item>()

        // Total matches page size exactly
        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 10))

        guard case .loaded = loader.phase else {
            Issue.record("Expected .loaded, got \(loader.phase)")
            return
        }
        #expect(loader.items.count == 10)
        #expect(!loader.hasMore)
    }

    // MARK: - Next Page Loading

    @Test @MainActor
    func loadNextPageAppendsItems() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 25))
        #expect(loader.items.count == 10)
        #expect(loader.hasMore)

        await loader.loadNextPage()
        #expect(loader.items.count == 20)
        #expect(loader.hasMore)

        await loader.loadNextPage()
        #expect(loader.items.count == 25)
        #expect(!loader.hasMore)
    }

    @Test @MainActor
    func loadNextPageNoOpsWhenNoMorePages() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 5))
        #expect(!loader.hasMore)

        await loader.loadNextPage()
        #expect(loader.items.count == 5)  // unchanged
    }

    @Test @MainActor
    func loadNextPageNoOpsWithoutFirstPage() async {
        let loader = PagedCollectionLoader<Item>()

        // No first page loaded — pageFetcher is nil
        await loader.loadNextPage()
        #expect(loader.items.isEmpty)
    }

    @Test @MainActor
    func loadNextPageDeduplicatesByID() async {
        let loader = PagedCollectionLoader<Item>()

        // Custom fetcher that returns overlapping IDs on page 2
        // Use startIndex to determine which page we're on instead of mutable counter
        await loader.loadFirstPage(pageSize: 5) { limit, startIndex in
            if startIndex == 0 {
                // First page: items 0-4
                let items = (0..<5).map { Item(id: $0) }
                return .init(items: items, totalCount: 10)
            } else {
                // Second page: includes overlapping item id=4
                let items = (4..<9).map { Item(id: $0) }
                return .init(items: items, totalCount: 10)
            }
        }
        #expect(loader.items.count == 5)

        await loader.loadNextPage()
        // Should have items 0-8 (9 unique), not 10 with a duplicate
        #expect(loader.items.count == 9)

        let ids = loader.items.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test @MainActor
    func loadNextPageStopsPagingOnError() async {
        let loader = PagedCollectionLoader<Item>()

        // Use startIndex to determine which page we're on instead of mutable counter
        await loader.loadFirstPage(pageSize: 5) { limit, startIndex in
            if startIndex == 0 {
                let items = (0..<5).map { Item(id: $0) }
                return .init(items: items, totalCount: 20)
            } else {
                throw TestError.simulated
            }
        }
        #expect(loader.hasMore)

        await loader.loadNextPage()
        // Error should stop further pagination but preserve existing items
        #expect(!loader.hasMore)
        #expect(loader.items.count == 5)  // Original items preserved
        guard case .loaded = loader.phase else {
            Issue.record("Phase should still be .loaded after pagination error")
            return
        }
    }

    // MARK: - onItemAppeared

    @Test @MainActor
    func onItemAppearedTriggersLoadForNearEndItem() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 20, Self.makeFetcher(totalItems: 50))
        #expect(loader.items.count == 20)

        // Trigger on the last item — should trigger a next page load
        let lastItem = loader.items.last!
        loader.onItemAppeared(lastItem, prefetchThreshold: 10)

        // Give the spawned Task time to complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(loader.items.count == 40)
    }

    @Test @MainActor
    func onItemAppearedNoOpsForEarlyItem() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 20, Self.makeFetcher(totalItems: 50))
        #expect(loader.items.count == 20)

        // Trigger on the first item — should NOT trigger a load
        let firstItem = loader.items.first!
        loader.onItemAppeared(firstItem, prefetchThreshold: 10)

        try? await Task.sleep(for: .milliseconds(100))

        #expect(loader.items.count == 20)  // Unchanged
    }

    @Test @MainActor
    func onItemAppearedNoOpsWhenNoMore() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 20, Self.makeFetcher(totalItems: 15))
        #expect(!loader.hasMore)

        let lastItem = loader.items.last!
        loader.onItemAppeared(lastItem, prefetchThreshold: 10)

        try? await Task.sleep(for: .milliseconds(100))

        #expect(loader.items.count == 15)  // Unchanged
    }

    // MARK: - Reset

    @Test @MainActor
    func resetClearsAllState() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 25))
        #expect(!loader.items.isEmpty)

        loader.reset()

        guard case .loading = loader.phase else {
            Issue.record("Expected .loading after reset, got \(loader.phase)")
            return
        }
        #expect(loader.items.isEmpty)
        #expect(loader.totalCount == 0)
        #expect(!loader.hasMore)
        #expect(!loader.isLoadingMore)
    }

    // MARK: - Reload / Re-fetch

    @Test @MainActor
    func loadFirstPageCanBeCalledMultipleTimes() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 5, Self.makeFetcher(totalItems: 10, namePrefix: "A"))
        #expect(loader.items.count == 5)
        #expect(loader.items.first?.name == "A 0")

        // Reload with different data
        await loader.loadFirstPage(pageSize: 5, Self.makeFetcher(totalItems: 3, namePrefix: "B"))
        #expect(loader.items.count == 3)
        #expect(loader.items.first?.name == "B 0")
        #expect(!loader.hasMore)
    }

    @Test @MainActor
    func loadFirstPageAfterFailureRecovery() async {
        let loader = PagedCollectionLoader<Item>()

        await loader.loadFirstPage(pageSize: 10) { _, _ in
            throw TestError.simulated
        }
        guard case .failed = loader.phase else {
            Issue.record("Expected .failed")
            return
        }

        // Retry with success
        await loader.loadFirstPage(pageSize: 10, Self.makeFetcher(totalItems: 5))
        guard case .loaded = loader.phase else {
            Issue.record("Expected .loaded after retry, got \(loader.phase)")
            return
        }
        #expect(loader.items.count == 5)
    }

    // MARK: - Page Struct

    @Test
    func pageStructStoresValues() {
        let page = PagedCollectionLoader<Item>.Page(
            items: [Item(id: 1), Item(id: 2)],
            totalCount: 100
        )
        #expect(page.items.count == 2)
        #expect(page.totalCount == 100)
    }

    // MARK: - Full Pagination Flow

    @Test @MainActor
    func fullPaginationFlowFromStartToEnd() async {
        let loader = PagedCollectionLoader<Item>()

        // Load 100 items in pages of 30
        await loader.loadFirstPage(pageSize: 30, Self.makeFetcher(totalItems: 100))
        #expect(loader.items.count == 30)
        #expect(loader.hasMore)
        #expect(loader.totalCount == 100)

        await loader.loadNextPage()
        #expect(loader.items.count == 60)
        #expect(loader.hasMore)

        await loader.loadNextPage()
        #expect(loader.items.count == 90)
        #expect(loader.hasMore)

        await loader.loadNextPage()
        #expect(loader.items.count == 100)
        #expect(!loader.hasMore)

        // Extra call should no-op
        await loader.loadNextPage()
        #expect(loader.items.count == 100)
    }

    // MARK: - Custom Page Size

    @Test @MainActor
    func customPageSizeIsRespected() async {
        let loader = PagedCollectionLoader<Item>()

        nonisolated(unsafe) var receivedLimit: Int?
        await loader.loadFirstPage(pageSize: 17) { limit, startIndex in
            receivedLimit = limit
            let items = (startIndex..<min(startIndex + limit, 50)).map { Item(id: $0) }
            return .init(items: items, totalCount: 50)
        }

        #expect(receivedLimit == 17)
        #expect(loader.items.count == 17)
    }

    @Test @MainActor
    func nextPagePassesCorrectStartIndex() async {
        let loader = PagedCollectionLoader<Item>()

        nonisolated(unsafe) var receivedStartIndices: [Int] = []
        await loader.loadFirstPage(pageSize: 10) { limit, startIndex in
            receivedStartIndices.append(startIndex)
            let endIndex = min(startIndex + limit, 30)
            let items = (startIndex..<endIndex).map { Item(id: $0) }
            return .init(items: items, totalCount: 30)
        }

        await loader.loadNextPage()
        await loader.loadNextPage()

        #expect(receivedStartIndices == [0, 10, 20])
    }
}
