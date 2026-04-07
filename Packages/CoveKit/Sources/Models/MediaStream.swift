import Foundation

public struct MediaStream: Codable, Hashable, Sendable {
    public let index: Int
    public let type: MediaStreamType
    public let codec: String?
    public let language: String?
    public let title: String?
    public let isExternal: Bool
    public let width: Int?
    public let height: Int?
    public let channels: Int?
    public let bitrate: Int?
    public let videoRange: String?
    public let videoRangeType: String?

    public init(
        index: Int,
        type: MediaStreamType,
        codec: String? = nil,
        language: String? = nil,
        title: String? = nil,
        isExternal: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        channels: Int? = nil,
        bitrate: Int? = nil,
        videoRange: String? = nil,
        videoRangeType: String? = nil
    ) {
        self.index = index
        self.type = type
        self.codec = codec
        self.language = language
        self.title = title
        self.isExternal = isExternal
        self.width = width
        self.height = height
        self.channels = channels
        self.bitrate = bitrate
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
    }
}
