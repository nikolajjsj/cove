import Foundation

public struct Episode: Identifiable, Codable, Hashable, Sendable {
    public let id: EpisodeID
    public let seriesId: SeriesID?
    public let seasonId: SeasonID?
    public let episodeNumber: Int?
    public let seasonNumber: Int?
    public let title: String
    public let overview: String?
    public let runtime: TimeInterval?
    public let userData: UserData?

    public init(
        id: EpisodeID,
        seriesId: SeriesID? = nil,
        seasonId: SeasonID? = nil,
        episodeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        title: String,
        overview: String? = nil,
        runtime: TimeInterval? = nil,
        userData: UserData? = nil
    ) {
        self.id = id
        self.seriesId = seriesId
        self.seasonId = seasonId
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.title = title
        self.overview = overview
        self.runtime = runtime
        self.userData = userData
    }
}
