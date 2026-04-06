import Foundation

public struct Track: Identifiable, Codable, Hashable, Sendable {
    public let id: TrackID
    public let title: String
    public let albumId: AlbumID?
    public let albumName: String?
    public let artistId: ArtistID?
    public let artistName: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let duration: TimeInterval?
    public let codec: String?
    public let bitRate: Int?
    public let sampleRate: Int?
    public let channelCount: Int?
    public let genres: [String]?
    public let userData: UserData?

    public init(
        id: TrackID,
        title: String,
        albumId: AlbumID? = nil,
        albumName: String? = nil,
        artistId: ArtistID? = nil,
        artistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        duration: TimeInterval? = nil,
        codec: String? = nil,
        bitRate: Int? = nil,
        sampleRate: Int? = nil,
        channelCount: Int? = nil,
        genres: [String]? = nil,
        userData: UserData? = nil
    ) {
        self.id = id
        self.title = title
        self.albumId = albumId
        self.albumName = albumName
        self.artistId = artistId
        self.artistName = artistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.codec = codec
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.genres = genres
        self.userData = userData
    }
}
