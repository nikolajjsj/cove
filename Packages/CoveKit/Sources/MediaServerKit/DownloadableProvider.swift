import Foundation
import Models

/// Optional capability protocol for servers that support downloading media.
public protocol DownloadableProvider: MediaServerProvider {
    func downloadURL(for item: MediaItem, profile: DeviceProfile?) async throws -> URL
}
