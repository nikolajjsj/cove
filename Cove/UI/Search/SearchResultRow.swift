import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct SearchResultRow: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        MediaItemRow(
            imageURL: thumbnailURL,
            title: item.title,
            subtitle: subtitle,
            mediaType: item.mediaType,
            thumbnailWidth: 50
        )
    }

    // MARK: - Helpers

    private var thumbnailURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 150, height: 225)
        )
    }

    private var subtitle: String {
        switch item.mediaType {
        case .movie, .series:
            if let year = item.productionYear {
                "\(year) · \(item.mediaType.displayLabel)"
            } else {
                item.mediaType.displayLabel
            }
        case .episode:
            episodeSubtitle
        case .track:
            trackSubtitle
        default:
            item.mediaType.displayLabel
        }
    }

    private var episodeSubtitle: String {
        var parts: [String] = []
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            parts.append("S\(season):E\(episode)")
        } else if let episode = item.indexNumber {
            parts.append("E\(episode)")
        }
        if let seriesName = item.seriesName {
            parts.append(seriesName)
        }
        return parts.isEmpty ? "Episode" : parts.joined(separator: " · ")
    }

    private var trackSubtitle: String {
        var parts: [String] = []
        if let artistName = item.artistName {
            parts.append(artistName)
        }
        if let albumName = item.albumName {
            parts.append(albumName)
        }
        return parts.isEmpty ? "Song" : parts.joined(separator: " · ")
    }
}
