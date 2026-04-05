import Foundation

public struct Artist: Identifiable, Codable, Hashable, Sendable {
    public let id: ArtistID
    public let name: String
    public let overview: String?
    public let sortName: String?
    public let albumCount: Int?

    public init(
        id: ArtistID,
        name: String,
        overview: String? = nil,
        sortName: String? = nil,
        albumCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.sortName = sortName
        self.albumCount = albumCount
    }
}
