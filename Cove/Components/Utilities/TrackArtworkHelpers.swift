import Foundation
import JellyfinProvider
import Models
import MediaServerKit

// MARK: - Track Artwork URL Helper

extension JellyfinServerProvider {
    /// Resolves the artwork URL for a track, preferring album artwork.
    ///
    /// Uses the album's primary image when available, falling back to the
    /// track's own primary image. Pass `maxSize` to control the requested image size.
    func artworkURL(for track: Track, maxSize: CGSize = CGSize(width: 600, height: 600)) -> URL? {
        let itemId = track.albumId ?? track.id
        return imageURL(for: itemId, type: .primary, maxSize: maxSize)
    }
}
