import Foundation

/// Response DTO for paginated item queries.
/// `GET /Users/{id}/Items`
public struct ItemsResult: Codable, Sendable {
    public let items: [BaseItemDto]?
    public let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}
