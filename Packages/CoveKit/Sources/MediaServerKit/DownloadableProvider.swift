import Foundation
import Models

/// Information needed to download a media item.
public struct DownloadInfo: Sendable {
    public let url: URL
    /// Expected file size in bytes, if known. Used for progress tracking when
    /// the server doesn't provide a Content-Length header (e.g. transcoded streams).
    public let expectedBytes: Int64?

    public init(url: URL, expectedBytes: Int64? = nil) {
        self.url = url
        self.expectedBytes = expectedBytes
    }
}

/// Optional capability protocol for servers that support downloading media.
public protocol DownloadableProvider: MediaServerProvider {
    func downloadInfo(for item: MediaItem, profile: DeviceProfile?) async throws -> DownloadInfo
}
