import Foundation

public struct SortOptions: Sendable {
    public let field: SortField
    public let order: SortOrder

    public init(field: SortField = .name, order: SortOrder = .ascending) {
        self.field = field
        self.order = order
    }
}

public enum SortField: String, Codable, Sendable {
    case name
    case dateAdded
    case dateCreated
    case datePlayed
    case premiereDate
    case communityRating
    case criticRating
    case runtime
    case random
    case albumArtist
    case album
}

public enum SortOrder: String, Codable, Sendable {
    case ascending
    case descending
}
