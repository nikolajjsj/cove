import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct SearchResultRow: View {
    let item: MediaItem
    @Environment(AppState.self) private var appState

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

            // Disclosure indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        switch item.mediaType {
        case .album, .artist:
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
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 150, height: 225)
        )
    }

    private var placeholderIcon: String {
        switch item.mediaType {
        case .movie: "film"
        case .series: "tv"
        case .album: "music.note"
        case .artist: "person"
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
        case .album:
            "Album"
        case .artist:
            "Artist"
        default:
            item.mediaType.rawValue.capitalized
        }
    }
}
