import Foundation

public struct UserData: Codable, Hashable, Sendable {
    public var isFavorite: Bool
    public var playbackPosition: TimeInterval
    public var playCount: Int
    public var isPlayed: Bool
    public var lastPlayedDate: Date?

    public init(
        isFavorite: Bool = false,
        playbackPosition: TimeInterval = 0,
        playCount: Int = 0,
        isPlayed: Bool = false,
        lastPlayedDate: Date? = nil
    ) {
        self.isFavorite = isFavorite
        self.playbackPosition = playbackPosition
        self.playCount = playCount
        self.isPlayed = isPlayed
        self.lastPlayedDate = lastPlayedDate
    }
}
