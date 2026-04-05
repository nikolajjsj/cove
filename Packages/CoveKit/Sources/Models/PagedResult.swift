import Foundation

/// A page of results from a paginated query.
public struct PagedResult<T: Sendable>: Sendable {
    /// The items in this page.
    public let items: [T]
    /// The index of the first item in this page (0-based).
    public let startIndex: Int
    /// Total number of items available on the server for this query.
    public let totalCount: Int

    /// Whether there are more items to load.
    public var hasMore: Bool {
        startIndex + items.count < totalCount
    }

    /// The startIndex to use for the next page request.
    public var nextStartIndex: Int {
        startIndex + items.count
    }

    public init(items: [T], startIndex: Int, totalCount: Int) {
        self.items = items
        self.startIndex = startIndex
        self.totalCount = totalCount
    }
}
