import Foundation

public struct StreamInfo: Sendable {
    public let url: URL
    public let playMethod: PlayMethod
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let mediaStreams: [MediaStream]
    public let mediaSourceId: String?

    /// The server-side session this stream belongs to, when it was resolved
    /// through `PlaybackInfo`. Playback reports must carry it so the server can
    /// tie them to the transcode job it started.
    public let session: PlaybackSession?

    /// Convenience: whether the server is transcoding (re-encoding) this stream.
    public var isTranscoded: Bool { playMethod == .transcode }

    /// Convenience: whether the file is being played as-is with no server processing.
    public var directPlaySupported: Bool { playMethod == .directPlay }

    public init(
        url: URL,
        playMethod: PlayMethod,
        container: String? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        mediaStreams: [MediaStream] = [],
        mediaSourceId: String? = nil,
        session: PlaybackSession? = nil
    ) {
        self.url = url
        self.playMethod = playMethod
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.mediaStreams = mediaStreams
        self.mediaSourceId = mediaSourceId
        self.session = session
    }
}
