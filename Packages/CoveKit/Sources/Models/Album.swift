import Foundation

public struct Album: Identifiable, Codable, Hashable, Sendable {
    public let id: AlbumID
    public let title: String
    public let artistId: ArtistID?
    public let artistName: String?
    public let year: Int?
    public let genre: String?
    public let trackCount: Int?
    public let duration: TimeInterval?
    public let userData: UserData?
    public let genres: [String]?
    public let dateAdded: Date?

    public init(
        id: AlbumID,
        title: String,
        artistId: ArtistID? = nil,
        artistName: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        trackCount: Int? = nil,
        duration: TimeInterval? = nil,
        userData: UserData? = nil,
        genres: [String]? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artistId = artistId
        self.artistName = artistName
        self.year = year
        self.genre = genre
        self.trackCount = trackCount
        self.duration = duration
        self.userData = userData
        self.genres = genres
        self.dateAdded = dateAdded
    }
}
