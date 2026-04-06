import Foundation
import Models

/// Optional capability protocol for servers that support video.
public protocol VideoProvider: MediaServerProvider {
    func seasons(series: SeriesID) async throws -> [Season]
    func episodes(season: SeasonID) async throws -> [Episode]
    func resumeItems() async throws -> [MediaItem]
    func streamURL(for item: MediaItem, profile: DeviceProfile?) async throws -> StreamInfo
    func specialFeatures(for item: MediaItem) async throws -> [MediaItem]
    func localTrailers(for item: MediaItem) async throws -> [MediaItem]
}
