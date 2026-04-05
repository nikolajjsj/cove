import Foundation

public struct Season: Identifiable, Codable, Hashable, Sendable {
    public let id: SeasonID
    public let seriesId: SeriesID
    public let seasonNumber: Int
    public let title: String
    public let episodeCount: Int?

    public init(
        id: SeasonID,
        seriesId: SeriesID,
        seasonNumber: Int,
        title: String,
        episodeCount: Int? = nil
    ) {
        self.id = id
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.title = title
        self.episodeCount = episodeCount
    }
}
