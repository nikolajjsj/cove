import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct LibraryItemCard: View {
    let item: MediaItem
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Poster image
            LazyImage(url: posterURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { ProgressView() }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: placeholderIcon)
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .aspectRatio(posterAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title
            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var posterURL: URL? {
        appState.provider.imageURL(
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
        }
    }
}
