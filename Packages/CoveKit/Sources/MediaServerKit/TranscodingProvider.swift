import Foundation
import Models

/// Optional capability protocol for servers that support transcoding.
public protocol TranscodingProvider: MediaServerProvider {
    func deviceProfile() -> DeviceProfile
    func transcodedStreamURL(for item: MediaItem, profile: DeviceProfile) async throws -> URL
}
