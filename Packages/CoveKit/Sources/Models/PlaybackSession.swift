import Foundation

/// Identifies a single server-side playback session.
///
/// Jellyfin issues a `PlaySessionId` from `POST /Items/{id}/PlaybackInfo` and uses
/// it to tie progress reports back to the transcode job (and any live stream) it
/// started for that session. Without it the server cannot match a stop report to
/// the ffmpeg process it spawned, so the process lingers until it times out.
///
/// Pass this to the `PlaybackReportingProvider` methods for anything resolved
/// through `PlaybackInfo`. Playback that bypasses it — the universal audio
/// endpoint, or a local downloaded file — has no session to report.
public struct PlaybackSession: Sendable, Hashable {

    /// The server's `PlaySessionId` for this session.
    public let playSessionId: String?

    /// How the server is delivering the media, so reports say what is really
    /// happening instead of always claiming direct play.
    public let playMethod: PlayMethod

    /// The live stream the server opened for this session, if any. Must be closed
    /// via `POST /LiveStreams/Close` when playback ends.
    public let liveStreamId: String?

    public init(
        playSessionId: String?,
        playMethod: PlayMethod,
        liveStreamId: String? = nil
    ) {
        self.playSessionId = playSessionId
        self.playMethod = playMethod
        self.liveStreamId = liveStreamId
    }
}
