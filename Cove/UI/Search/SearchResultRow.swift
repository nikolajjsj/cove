import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct SearchResultRow: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnail

            // Title & subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        switch item.mediaType {
        case .album, .artist, .track:
            MediaImage.artwork(url: thumbnailURL, cornerRadius: 6)
                .frame(width: 50, height: 50)
        default:
            MediaImage.poster(
                url: thumbnailURL,
                aspectRatio: 2.0 / 3.0,
                icon: placeholderIcon,
                cornerRadius: 6
            )
            .frame(width: 50, height: 75)
        }
    }

    // MARK: - Helpers

    private var thumbnailURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 150, height: 225)
        )
    }

    private var placeholderIcon: String {
        switch item.mediaType {
        case .movie: "film"
        case .series: "tv"
        case .episode: "tv"
        case .album: "music.note"
        case .artist: "person"
        case .track: "music.note"
        default: "photo"
        }
    }

    private var subtitle: String {
        switch item.mediaType {
        case .movie:
            if let year = item.productionYear {
                "\(year) · Movie"
            } else {
                "Movie"
            }
        case .series:
            if let year = item.productionYear {
                "\(year) · TV Show"
            } else {
                "TV Show"
            }
        case .episode:
            episodeSubtitle
        case .album:
            "Album"
        case .artist:
            "Artist"
        case .track:
            trackSubtitle
        default:
            item.mediaType.rawValue.capitalized
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
