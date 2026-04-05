import Foundation

public struct Movie: Identifiable, Codable, Hashable, Sendable {
    public let id: MovieID
    public let title: String
    public let overview: String?
    public let year: Int?
    public let runtime: TimeInterval?
    public let genres: [String]
    public let communityRating: Double?
    public let criticRating: Double?

    public init(
        id: MovieID,
        title: String,
        overview: String? = nil,
        year: Int? = nil,
        runtime: TimeInterval? = nil,
        genres: [String] = [],
        communityRating: Double? = nil,
        criticRating: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.year = year
        self.runtime = runtime
        self.genres = genres
        self.communityRating = communityRating
        self.criticRating = criticRating
    }
}
