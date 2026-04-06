import Foundation

// MARK: - DeviceProfile

/// Describes the playback capabilities of the current device.
/// Matches the Jellyfin server's DeviceProfile JSON schema.
public struct DeviceProfile: Codable, Sendable {
    public let name: String
    public let maxStreamingBitrate: Int?
    public let directPlayProfiles: [DirectPlayProfile]
    public let transcodingProfiles: [TranscodingProfile]
    public let containerProfiles: [ContainerProfile]
    public let codecProfiles: [CodecProfile]
    public let subtitleProfiles: [SubtitleProfile]

    public init(
        name: String,
        maxStreamingBitrate: Int? = nil,
        directPlayProfiles: [DirectPlayProfile] = [],
        transcodingProfiles: [TranscodingProfile] = [],
        containerProfiles: [ContainerProfile] = [],
        codecProfiles: [CodecProfile] = [],
        subtitleProfiles: [SubtitleProfile] = []
    ) {
        self.name = name
        self.maxStreamingBitrate = maxStreamingBitrate
        self.directPlayProfiles = directPlayProfiles
        self.transcodingProfiles = transcodingProfiles
        self.containerProfiles = containerProfiles
        self.codecProfiles = codecProfiles
        self.subtitleProfiles = subtitleProfiles
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case containerProfiles = "ContainerProfiles"
        case codecProfiles = "CodecProfiles"
        case subtitleProfiles = "SubtitleProfiles"
    }
}

// MARK: - DirectPlayProfile

public struct DirectPlayProfile: Codable, Sendable {
    public let container: String
    public let type: ProfileType
    public let videoCodec: String?
    public let audioCodec: String?

    public init(
        container: String,
        type: ProfileType,
        videoCodec: String? = nil,
        audioCodec: String? = nil
    ) {
        self.container = container
        self.type = type
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
    }

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
    }
}

// MARK: - TranscodingProfile

public struct TranscodingProfile: Codable, Sendable {
    public let container: String
    public let type: ProfileType
    public let videoCodec: String
    public let audioCodec: String
    public let `protocol`: String
    public let context: String
    public let maxAudioChannels: String?
    public let breakOnNonKeyFrames: Bool?
    public let copyTimestamps: Bool?

    public init(
        container: String,
        type: ProfileType,
        videoCodec: String,
        audioCodec: String,
        protocol: String,
        context: String,
        maxAudioChannels: String? = nil,
        breakOnNonKeyFrames: Bool? = nil,
        copyTimestamps: Bool? = nil
    ) {
        self.container = container
        self.type = type
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.`protocol` = `protocol`
        self.context = context
        self.maxAudioChannels = maxAudioChannels
        self.breakOnNonKeyFrames = breakOnNonKeyFrames
        self.copyTimestamps = copyTimestamps
    }

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case `protocol` = "Protocol"
        case context = "Context"
        case maxAudioChannels = "MaxAudioChannels"
        case breakOnNonKeyFrames = "BreakOnNonKeyFrames"
        case copyTimestamps = "CopyTimestamps"
    }
}

// MARK: - ContainerProfile

public struct ContainerProfile: Codable, Sendable {
    public let type: ProfileType
    public let container: String
    public let conditions: [ProfileCondition]?

    public init(
        type: ProfileType,
        container: String,
        conditions: [ProfileCondition]? = nil
    ) {
        self.type = type
        self.container = container
        self.conditions = conditions
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case container = "Container"
        case conditions = "Conditions"
    }
}

// MARK: - CodecProfile

public struct CodecProfile: Codable, Sendable {
    public let type: CodecType
    public let codec: String?
    public let conditions: [ProfileCondition]?

    public init(
        type: CodecType,
        codec: String? = nil,
        conditions: [ProfileCondition]? = nil
    ) {
        self.type = type
        self.codec = codec
        self.conditions = conditions
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
        case conditions = "Conditions"
    }
}

// MARK: - SubtitleProfile

public struct SubtitleProfile: Codable, Sendable {
    public let format: String
    public let method: SubtitleMethod

    public init(
        format: String,
        method: SubtitleMethod
    ) {
        self.format = format
        self.method = method
    }

    enum CodingKeys: String, CodingKey {
        case format = "Format"
        case method = "Method"
    }
}

// MARK: - ProfileCondition

public struct ProfileCondition: Codable, Sendable {
    public let condition: ProfileConditionType
    public let property: ProfileConditionProperty
    public let value: String?
    public let isRequired: Bool?

    public init(
        condition: ProfileConditionType,
        property: ProfileConditionProperty,
        value: String? = nil,
        isRequired: Bool? = nil
    ) {
        self.condition = condition
        self.property = property
        self.value = value
        self.isRequired = isRequired
    }

    enum CodingKeys: String, CodingKey {
        case condition = "Condition"
        case property = "Property"
        case value = "Value"
        case isRequired = "IsRequired"
    }
}

// MARK: - Enums

public enum ProfileType: String, Codable, Sendable {
    case video = "Video"
    case audio = "Audio"
    case photo = "Photo"
}

public enum CodecType: String, Codable, Sendable {
    case video = "Video"
    case videoAudio = "VideoAudio"
    case audio = "Audio"
}

public enum SubtitleMethod: String, Codable, Sendable {
    case encode = "Encode"
    case embed = "Embed"
    case external = "External"
    case hls = "Hls"
    case drop = "Drop"
}

public enum ProfileConditionType: String, Codable, Sendable {
    case equals = "Equals"
    case notEquals = "NotEquals"
    case lessThanEqual = "LessThanEqual"
    case greaterThanEqual = "GreaterThanEqual"
}

public enum ProfileConditionProperty: String, Codable, Sendable {
    case audioChannels = "AudioChannels"
    case audioBitrate = "AudioBitrate"
    case videoBitrate = "VideoBitrate"
    case videoLevel = "VideoLevel"
    case width = "Width"
    case height = "Height"
    case refFrames = "RefFrames"
}

// MARK: - Apple Device Factory

extension DeviceProfile {
    /// Build the conservative AVPlayer profile for Apple devices.
    public static func appleDevice(
        name: String = "Cove",
        maxStreamingBitrate: Int = 120_000_000
    ) -> DeviceProfile {
        DeviceProfile(
            name: name,
            maxStreamingBitrate: maxStreamingBitrate,
            directPlayProfiles: [
                DirectPlayProfile(
                    container: "mp4,m4v,mov",
                    type: .video,
                    videoCodec: "h264,hevc",
                    audioCodec: "aac,mp3,alac,flac,ac3,eac3"
                )
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    container: "ts",
                    type: .video,
                    videoCodec: "h264",
                    audioCodec: "aac,mp3,ac3,eac3,flac,alac",
                    protocol: "hls",
                    context: "Streaming",
                    maxAudioChannels: "6",
                    breakOnNonKeyFrames: true,
                    copyTimestamps: false
                )
            ],
            containerProfiles: [],
            codecProfiles: [],
            subtitleProfiles: [
                SubtitleProfile(format: "srt", method: .external),
                SubtitleProfile(format: "vtt", method: .external),
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode),
                SubtitleProfile(format: "pgs", method: .encode),
                SubtitleProfile(format: "pgssub", method: .encode),
                SubtitleProfile(format: "dvdsub", method: .encode),
                SubtitleProfile(format: "sub", method: .encode),
            ]
        )
    }
}
