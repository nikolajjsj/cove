import Foundation

public struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public let title: String
    public let overview: String?
    public let mediaType: MediaType
    public let dateAdded: Date?
    public let productionYear: Int?
    public let genres: [String]?
    public let runTimeTicks: Int64?
    public let communityRating: Double?
    public let officialRating: String?
    public let criticRating: Double?
    public let people: [Person]
    public let remoteTrailerURLs: [URL]
    public var userData: UserData?

    /// Runtime in seconds, derived from `runTimeTicks`.
    public var runtime: TimeInterval? {
        runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
    }

    public init(
        id: ItemID,
        title: String,
        overview: String? = nil,
        mediaType: MediaType,
        dateAdded: Date? = nil,
        productionYear: Int? = nil,
        genres: [String]? = nil,
        runTimeTicks: Int64? = nil,
        communityRating: Double? = nil,
        officialRating: String? = nil,
        criticRating: Double? = nil,
        people: [Person] = [],
        remoteTrailerURLs: [URL] = [],
        userData: UserData? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.mediaType = mediaType
        self.dateAdded = dateAdded
        self.productionYear = productionYear
        self.genres = genres
        self.runTimeTicks = runTimeTicks
        self.communityRating = communityRating
        self.officialRating = officialRating
        self.criticRating = criticRating
        self.people = people
        self.remoteTrailerURLs = remoteTrailerURLs
        self.userData = userData
    }
}
