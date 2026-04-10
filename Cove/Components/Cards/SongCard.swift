import Models
import SwiftUI

/// A self-contained song card for horizontal shelves with tap-to-play and context menu.
///
/// Unlike `AlbumCard` and `ArtistCard`, tapping a song card plays it rather than
/// navigating. The full `.mediaContextMenu(item:)` is built in.
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
        .mediaContextMenu(item: item)
    }

    private var cardContent: some View {
        MediaCardContent(
            imageURL: imageURL,
            title: item.title,
            subtitle: subtitle
        )
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
