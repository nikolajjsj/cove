import Foundation

public struct Album: Identifiable, Codable, Hashable, Sendable {
    public let id: AlbumID
    public let title: String
    public let artistId: ArtistID?
    public let artistName: String?
    public let year: Int?
    public let genres: [String]?
    public let dateAdded: Date?
    public let trackCount: Int?
    public let duration: TimeInterval?
    public let userData: UserData?

    /// Convenience accessor for the first genre. Equivalent to `genres?.first`.
    public var genre: String? { genres?.first }

    public init(
        id: AlbumID,
        title: String,
        artistId: ArtistID? = nil,
        artistName: String? = nil,
        year: Int? = nil,
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
        self.trackCount = trackCount
        self.duration = duration
        self.userData = userData
        self.genres = genres
        self.dateAdded = dateAdded
    }
}
