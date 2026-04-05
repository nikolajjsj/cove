import Foundation

/// DTO representing a Jellyfin item. Used in browse/search/detail responses.
/// Only includes fields we actually use.
public struct BaseItemDto: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let overview: String?
    public let type: String?
    public let dateCreated: String?
    public let premiereDate: String?
    public let productionYear: Int?
    public let communityRating: Double?
    public let criticRating: Double?
    public let officialRating: String?
    public let runTimeTicks: Int64?
    public let genres: [String]?
    public let seriesId: String?
    public let seriesName: String?
    public let seasonId: String?
    public let parentIndexNumber: Int?
    public let indexNumber: Int?
    public let albumId: String?
    public let albumArtist: String?
    public let album: String?
    public let artistItems: [NameIdPair]?
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let userData: BaseItemUserData?
    public let collectionType: String?

    public init(
        id: String? = nil,
        name: String? = nil,
        overview: String? = nil,
        type: String? = nil,
        dateCreated: String? = nil,
        premiereDate: String? = nil,
        productionYear: Int? = nil,
        communityRating: Double? = nil,
        criticRating: Double? = nil,
        officialRating: String? = nil,
        runTimeTicks: Int64? = nil,
        genres: [String]? = nil,
        seriesId: String? = nil,
        seriesName: String? = nil,
        seasonId: String? = nil,
        parentIndexNumber: Int? = nil,
        indexNumber: Int? = nil,
        albumId: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        artistItems: [NameIdPair]? = nil,
        imageTags: [String: String]? = nil,
        backdropImageTags: [String]? = nil,
        userData: BaseItemUserData? = nil,
        collectionType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.type = type
        self.dateCreated = dateCreated
        self.premiereDate = premiereDate
        self.productionYear = productionYear
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.officialRating = officialRating
        self.runTimeTicks = runTimeTicks
        self.genres = genres
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.seasonId = seasonId
        self.parentIndexNumber = parentIndexNumber
        self.indexNumber = indexNumber
        self.albumId = albumId
        self.albumArtist = albumArtist
        self.album = album
        self.artistItems = artistItems
        self.imageTags = imageTags
        self.backdropImageTags = backdropImageTags
        self.userData = userData
        self.collectionType = collectionType
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case type = "Type"
        case dateCreated = "DateCreated"
        case premiereDate = "PremiereDate"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case officialRating = "OfficialRating"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case albumId = "AlbumId"
        case albumArtist = "AlbumArtist"
        case album = "Album"
        case artistItems = "ArtistItems"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case userData = "UserData"
        case collectionType = "CollectionType"
    }
}

/// A simple name/id pair used for artist items and similar nested references.
public struct NameIdPair: Codable, Sendable {
    public let name: String?
    public let id: String?

    public init(name: String? = nil, id: String? = nil) {
        self.name = name
        self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

/// User-specific data attached to a Jellyfin item (play state, favorite status, etc.).
public struct BaseItemUserData: Codable, Sendable {
    public let isFavorite: Bool?
    public let playbackPositionTicks: Int64?
    public let playCount: Int?
    public let played: Bool?
    public let lastPlayedDate: String?

    public init(
        isFavorite: Bool? = nil,
        playbackPositionTicks: Int64? = nil,
        playCount: Int? = nil,
        played: Bool? = nil,
        lastPlayedDate: String? = nil
    ) {
        self.isFavorite = isFavorite
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.played = played
        self.lastPlayedDate = lastPlayedDate
    }

    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case played = "Played"
        case lastPlayedDate = "LastPlayedDate"
    }
}
