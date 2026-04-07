import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct LibraryItemCard: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Poster image
            MediaImage.poster(
                url: posterURL,
                aspectRatio: posterAspectRatio,
                icon: placeholderIcon,
                cornerRadius: 8
            )

            // Title
            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .mediaContextMenu(item: item)
    }

    // MARK: - Helpers

    private var posterURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }

    private var posterAspectRatio: CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist:
            1.0  // Square for music
        default:
            2.0 / 3.0  // Portrait for video
        }
    }

    private var placeholderIcon: String {
        switch item.mediaType {
        case .movie: "film"
        case .series: "tv"
        case .episode: "play.rectangle"
        case .album: "music.note"
        case .artist: "person"
        case .track: "music.note"
        case .playlist: "music.note.list"
        case .collection: "rectangle.stack.fill"
        case .season: "tv"
        case .book: "book"
        case .podcast: "mic"
        case .genre: "guitars"
        }
    }
}
