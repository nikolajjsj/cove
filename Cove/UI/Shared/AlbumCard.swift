import CoveUI
import Models
import SwiftUI

/// A self-contained album card that includes navigation and context menu.
///
/// Wraps a `NavigationLink(value:)` to the album's `MediaItem` and attaches
/// the full `.mediaContextMenu(item:)` modifier, so call-sites never need
/// to remember to add either.
///
/// Works in both grid and shelf contexts:
/// ```swift
/// // In a LazyVGrid (fills cell width):
/// AlbumCard(item: album, imageURL: url)
///
/// // In a horizontal shelf (fixed width):
/// AlbumCard(item: album, imageURL: url)
///     .frame(width: 140)
/// ```
struct AlbumCard: View {
    let item: MediaItem
    let subtitle: String?
    let imageURL: URL?

    init(item: MediaItem, subtitle: String? = nil, imageURL: URL?) {
        self.item = item
        self.subtitle = subtitle
        self.imageURL = imageURL
    }

    /// Convenience init for `Album` model (used in ArtistDetailView).
    init(album: Album, subtitle: String? = nil, imageURL: URL?) {
        self.item = MediaItem(id: album.id, title: album.title, mediaType: .album)
        self.subtitle = subtitle
        self.imageURL = imageURL
    }

    var body: some View {
        NavigationLink(value: item) {
            cardContent
        }
        .buttonStyle(.plain)
        .mediaContextMenu(item: item)
    }

    private var cardContent: some View {
        MediaCardContent(
            imageURL: imageURL,
            title: item.title,
            subtitle: subtitle,
            titleLineLimit: 2,
            reservesSpace: true
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
            AlbumCard(
                item: MediaItem(id: ItemID("1"), title: "Abbey Road", mediaType: .album),
                imageURL: nil
            )
            AlbumCard(
                item: MediaItem(id: ItemID("2"), title: "Dark Side of the Moon", mediaType: .album),
                subtitle: "Pink Floyd",
                imageURL: nil
            )
        }
        .padding()
        .environment(AppState.preview)
    }
}
