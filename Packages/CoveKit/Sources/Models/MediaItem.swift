import Foundation

public struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public let title: String
    public let overview: String?
    public let mediaType: MediaType
    public let dateAdded: Date?
    public var userData: UserData?

    public init(
        id: ItemID,
        title: String,
        overview: String? = nil,
        mediaType: MediaType,
        dateAdded: Date? = nil,
        userData: UserData? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.mediaType = mediaType
        self.dateAdded = dateAdded
        self.userData = userData
    }
}
