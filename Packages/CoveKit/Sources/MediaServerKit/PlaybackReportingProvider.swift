import Foundation
import Models

/// Optional capability protocol for servers that accept playback reports.
public protocol PlaybackReportingProvider: MediaServerProvider {
    func reportPlaybackStart(item: MediaItem, position: TimeInterval) async throws
    func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws
    func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws
}
