import CoveUI
import Models
import SwiftUI

/// A self-contained song card for horizontal shelves with tap-to-play and context menu.
///
/// Unlike `AlbumCard` and `ArtistCard`, tapping a song card plays it rather than
/// navigating. The full `.trackContextMenu(track:)` is built in.
///
/// ```swift
/// SongCard(item: song, imageURL: url) {
///     playSong(at: index)
/// }
/// ```
struct SongCard: View {
    let item: MediaItem
    let subtitle: String?
    let imageURL: URL?
    let onTap: () -> Void

    /// The `Track` constructed from the `MediaItem`, used for the context menu.
    private var track: Track {
        Track(
            id: TrackID(item.id.rawValue),
            title: item.title,
            albumId: item.albumId.map { AlbumID($0.rawValue) },
            albumName: item.albumName,
            artistName: item.artistName,
            duration: item.runtime,
            userData: item.userData
        )
    }

    init(
        item: MediaItem,
        subtitle: String? = nil,
        imageURL: URL?,
        onTap: @escaping () -> Void
    ) {
        self.item = item
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .trackContextMenu(track: track)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        SongCard(
            item: MediaItem(
                id: ItemID("1"),
                title: "Come Together",
                mediaType: .track,
                artistName: "The Beatles"
            ),
            subtitle: "The Beatles",
            imageURL: nil
        ) {
            // play action
        }
        .frame(width: 140)

        SongCard(
            item: MediaItem(
                id: ItemID("2"),
                title: "Hey Jude",
                mediaType: .track,
                artistName: "The Beatles"
            ),
            subtitle: "The Beatles",
            imageURL: nil
        ) {
            // play action
        }
        .frame(width: 140)
    }
    .padding()
    .environment(AppState.preview)
}
