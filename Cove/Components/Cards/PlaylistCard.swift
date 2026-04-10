import Models
import SwiftUI

/// A self-contained playlist card that includes navigation and context menu.
///
/// Wraps a `NavigationLink(value:)` to the `Playlist` and attaches
/// the full `.playlistContextMenu(playlist:)` modifier, so call-sites never
/// need to remember to add either.
///
/// Works in both grid and shelf contexts:
/// ```swift
/// // In a LazyVGrid (fills cell width):
/// PlaylistCard(playlist: playlist, imageURL: url)
///
/// // In a horizontal shelf (fixed width):
/// PlaylistCard(playlist: playlist, imageURL: url)
///     .frame(width: 140)
/// ```
struct PlaylistCard: View {
    let playlist: Playlist
    let subtitle: String?
    let imageURL: URL?

    init(playlist: Playlist, subtitle: String? = nil, imageURL: URL?) {
        self.playlist = playlist
        self.subtitle = subtitle ?? Self.defaultSubtitle(for: playlist)
        self.imageURL = imageURL
    }

    var body: some View {
        NavigationLink(value: playlist) {
            cardContent
        }
        .buttonStyle(.plain)
        .playlistContextMenu(playlist: playlist)
    }

    private var cardContent: some View {
        MediaCardContent(
            imageURL: imageURL,
            title: playlist.name,
            subtitle: subtitle,
            titleLineLimit: 2,
            reservesSpace: true
        )
    }

    // MARK: - Helpers

    /// Builds a human-readable track count subtitle from the playlist's `itemCount`.
    private static func defaultSubtitle(for playlist: Playlist) -> String? {
        guard let count = playlist.itemCount else { return nil }
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
            PlaylistCard(
                playlist: Playlist(
                    id: PlaylistID("1"),
                    name: "Road Trip Mix",
                    itemCount: 24
                ),
                imageURL: nil
            )
            PlaylistCard(
                playlist: Playlist(
                    id: PlaylistID("2"),
                    name: "Chill Vibes",
                    itemCount: 1
                ),
                imageURL: nil
            )
            PlaylistCard(
                playlist: Playlist(
                    id: PlaylistID("3"),
                    name: "Empty Playlist"
                ),
                imageURL: nil
            )
        }
        .padding()
        .environment(AppState.preview)
    }
}
