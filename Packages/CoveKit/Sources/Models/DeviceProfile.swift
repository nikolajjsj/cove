import Foundation

/// Describes the playback capabilities of the current device.
/// Used by providers to decide between direct play, remux, or transcode.
public struct DeviceProfile: Sendable {
    public let name: String
    public let maxStreamingBitrate: Int?
    public let supportedVideoCodecs: [String]
    public let supportedAudioCodecs: [String]
    public let supportedContainers: [String]
    public let supportsDirectPlay: Bool
    public let supportsDirectStream: Bool
    public let supportsTranscoding: Bool

    public init(
        name: String,
        maxStreamingBitrate: Int? = nil,
        supportedVideoCodecs: [String] = [],
        supportedAudioCodecs: [String] = [],
        supportedContainers: [String] = [],
        supportsDirectPlay: Bool = true,
        supportsDirectStream: Bool = true,
        supportsTranscoding: Bool = true
    ) {
        self.name = name
        self.maxStreamingBitrate = maxStreamingBitrate
        self.supportedVideoCodecs = supportedVideoCodecs
        self.supportedAudioCodecs = supportedAudioCodecs
        self.supportedContainers = supportedContainers
        self.supportsDirectPlay = supportsDirectPlay
        self.supportsDirectStream = supportsDirectStream
        self.supportsTranscoding = supportsTranscoding
    }
}
