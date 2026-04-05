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
        codec: String? = nil
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
    }
}
