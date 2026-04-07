import CoveUI
import Models
import SwiftUI

/// A self-contained artist card that includes navigation and context menu.
///
/// Wraps a `NavigationLink(value:)` to the artist's `MediaItem` and attaches
/// the full `.artistContextMenu(artist:)` modifier, so call-sites never need
/// to remember to add either.
///
/// Works in both grid and shelf contexts:
/// ```swift
/// // In a LazyVGrid (fills cell width):
/// ArtistCard(item: artist, imageURL: url)
///
/// // In a horizontal shelf (fixed width):
/// ArtistCard(item: artist, imageURL: url)
///     .frame(width: 120)
/// ```
struct ArtistCard: View {
    let item: MediaItem
    let imageURL: URL?

    var body: some View {
        NavigationLink(value: item) {
            cardContent
        }
        .buttonStyle(.plain)
        .artistContextMenu(artist: item)
    }

    private var cardContent: some View {
        VStack(spacing: 8) {
            MediaImage.artwork(url: imageURL, cornerRadius: .infinity)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HStack(spacing: 16) {
            ArtistCard(
                item: MediaItem(id: ItemID("1"), title: "The Beatles", mediaType: .artist),
                imageURL: nil
            )
            .frame(width: 120)

            ArtistCard(
                item: MediaItem(id: ItemID("2"), title: "Pink Floyd", mediaType: .artist),
                imageURL: nil
            )
            .frame(width: 120)
        }
        .padding()
        .environment(AppState.preview)
    }
}
