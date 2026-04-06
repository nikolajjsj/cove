import Foundation

public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public let id: PlaylistID
    public let name: String
    public let overview: String?
    public let itemCount: Int?
    public let duration: TimeInterval?
    public let userData: UserData?
    public let dateAdded: Date?

    public init(
        id: PlaylistID,
        name: String,
        overview: String? = nil,
        itemCount: Int? = nil,
        duration: TimeInterval? = nil,
        userData: UserData? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.itemCount = itemCount
        self.duration = duration
        self.userData = userData
        self.dateAdded = dateAdded
    }
}
