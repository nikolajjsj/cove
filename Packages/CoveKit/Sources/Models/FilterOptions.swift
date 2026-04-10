import Foundation

public struct FilterOptions: Sendable {
    public let mediaTypes: [MediaType]?
    public let genres: [String]?
    public let years: [Int]?
    public let isFavorite: Bool?
    public let isPlayed: Bool?
    public let parentId: ItemID?
    public let limit: Int?
    public let startIndex: Int?
    public let searchTerm: String?
    public let includeItemTypes: [String]?
    public let minCommunityRating: Double?

    public init(
        mediaTypes: [MediaType]? = nil,
        genres: [String]? = nil,
        years: [Int]? = nil,
        isFavorite: Bool? = nil,
        isPlayed: Bool? = nil,
        parentId: ItemID? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        searchTerm: String? = nil,
        includeItemTypes: [String]? = nil,
        minCommunityRating: Double? = nil
    ) {
        self.mediaTypes = mediaTypes
        self.genres = genres
        self.years = years
        self.isFavorite = isFavorite
        self.isPlayed = isPlayed
        self.parentId = parentId
        self.limit = limit
        self.startIndex = startIndex
        self.searchTerm = searchTerm
        self.includeItemTypes = includeItemTypes
        self.minCommunityRating = minCommunityRating
    }
}
