import Foundation

/// Response from `POST /Items/{id}/PlaybackInfo`
public struct PlaybackInfoResponse: Codable, Sendable {
    public let mediaSources: [MediaSourceInfo]?
    public let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

/// Describes a media source (file/stream) for a given item.
public struct MediaSourceInfo: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let container: String?
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let supportsTranscoding: Bool?
    public let transcodingUrl: String?
    public let mediaStreams: [MediaStreamInfo]?
    public let bitrate: Int?
    public let size: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case mediaStreams = "MediaStreams"
        case bitrate = "Bitrate"
        case size = "Size"
    }
}

/// Describes a single media stream (video/audio/subtitle) within a media source.
public struct MediaStreamInfo: Codable, Sendable {
    public let index: Int?
    public let type: String?  // "Video", "Audio", "Subtitle"
    public let codec: String?
    public let language: String?
    public let title: String?
    public let isExternal: Bool?
    public let isDefault: Bool?
    public let isForced: Bool?
    public let deliveryMethod: String?  // "External", "Embed"
    public let deliveryUrl: String?
    public let displayTitle: String?
    public let height: Int?
    public let width: Int?
    public let channels: Int?
    public let bitRate: Int?
    public let sampleRate: Int?
    public let videoRange: String?
    public let videoRangeType: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case language = "Language"
        case title = "Title"
        case isExternal = "IsExternal"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case deliveryMethod = "DeliveryMethod"
        case deliveryUrl = "DeliveryUrl"
        case displayTitle = "DisplayTitle"
        case height = "Height"
        case width = "Width"
        case channels = "Channels"
        case bitRate = "BitRate"
        case sampleRate = "SampleRate"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
    }
}
