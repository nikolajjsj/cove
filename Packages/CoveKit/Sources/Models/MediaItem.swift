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
    public let providerIds: ProviderIds?
    public let studios: [String]?
    public let tagline: String?
    public let originalTitle: String?
    public let premiereDate: Date?
    public let endDate: Date?
    public let mediaStreams: [MediaStream]?
    public let people: [Person]
    public let remoteTrailerURLs: [URL]
    public var userData: UserData?

    // Audio-specific fields (populated for tracks/songs, nil for other types)
    public let artistName: String?
    public let albumName: String?
    public let albumId: ItemID?

    // Image metadata (maps image type to its cache tag; nil or missing key means that image type doesn't exist)
    public let imageTags: [ImageType: String]?

    // Episode/series metadata (for Continue Watching / Up Next cards)
    public let seriesName: String?
    public let seriesId: ItemID?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?

    // Chapter markers within the media item
    public let chapters: [Chapter]

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
        providerIds: ProviderIds? = nil,
        studios: [String]? = nil,
        tagline: String? = nil,
        originalTitle: String? = nil,
        premiereDate: Date? = nil,
        endDate: Date? = nil,
        mediaStreams: [MediaStream]? = nil,
        people: [Person] = [],
        remoteTrailerURLs: [URL] = [],
        userData: UserData? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        albumId: ItemID? = nil,
        imageTags: [ImageType: String]? = nil,
        seriesName: String? = nil,
        seriesId: ItemID? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        chapters: [Chapter] = []
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
        self.providerIds = providerIds
        self.studios = studios
        self.tagline = tagline
        self.originalTitle = originalTitle
        self.premiereDate = premiereDate
        self.endDate = endDate
        self.mediaStreams = mediaStreams
        self.people = people
        self.remoteTrailerURLs = remoteTrailerURLs
        self.userData = userData
        self.artistName = artistName
        self.albumName = albumName
        self.albumId = albumId
        self.imageTags = imageTags
        self.seriesName = seriesName
        self.seriesId = seriesId
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.chapters = chapters
    }
}
