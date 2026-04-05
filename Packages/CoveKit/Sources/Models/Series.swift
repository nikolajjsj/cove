import Foundation

public struct Series: Identifiable, Codable, Hashable, Sendable {
    public let id: SeriesID
    public let title: String
    public let overview: String?
    public let year: Int?
    public let status: String?
    public let genres: [String]
    public let seasonCount: Int?
    public let episodeCount: Int?

    public init(
        id: SeriesID,
        title: String,
        overview: String? = nil,
        year: Int? = nil,
        status: String? = nil,
        genres: [String] = [],
        seasonCount: Int? = nil,
        episodeCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.year = year
        self.status = status
        self.genres = genres
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
    }
}
