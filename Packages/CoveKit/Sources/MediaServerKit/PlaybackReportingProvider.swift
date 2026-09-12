import Foundation
import Models

/// Optional capability protocol for servers that accept playback reports.
public protocol PlaybackReportingProvider: MediaServerProvider {
    func reportPlaybackStart(
        item: MediaItem, position: TimeInterval, session: PlaybackSession?
    ) async throws
    func reportPlaybackProgress(
        item: MediaItem, position: TimeInterval, isPaused: Bool, session: PlaybackSession?
    ) async throws
    func reportPlaybackStopped(
        item: MediaItem, position: TimeInterval, session: PlaybackSession?
    ) async throws

    /// Release a live stream the server opened for a playback session.
    func closeLiveStream(id: String) async throws
}

extension PlaybackReportingProvider {

    /// Report against playback with no server-side session — a local downloaded
    /// file, or a stream the client built itself rather than resolving through
    /// `PlaybackInfo`.
    public func reportPlaybackStart(item: MediaItem, position: TimeInterval) async throws {
        try await reportPlaybackStart(item: item, position: position, session: nil)
    }

    /// Convenience overload that defaults `isPaused` to `false`.
    public func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws {
        try await reportPlaybackProgress(
            item: item, position: position, isPaused: false, session: nil)
    }

    public func reportPlaybackProgress(
        item: MediaItem, position: TimeInterval, isPaused: Bool
    ) async throws {
        try await reportPlaybackProgress(
            item: item, position: position, isPaused: isPaused, session: nil)
    }

    public func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws {
        try await reportPlaybackStopped(item: item, position: position, session: nil)
    }
}
