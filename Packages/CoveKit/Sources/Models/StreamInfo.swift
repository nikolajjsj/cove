import Foundation

public struct StreamInfo: Sendable {
    public let url: URL
    public let isTranscoded: Bool
    public let mediaStreams: [MediaStream]
    public let directPlaySupported: Bool

    public init(
        url: URL,
        isTranscoded: Bool,
        mediaStreams: [MediaStream] = [],
        directPlaySupported: Bool
    ) {
        self.url = url
        self.isTranscoded = isTranscoded
        self.mediaStreams = mediaStreams
        self.directPlaySupported = directPlaySupported
    }
}
