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
                aspectRatio: item.mediaType.isMusic ? 1.0 : 2.0 / 3.0,
                icon: item.mediaType.placeholderIcon,
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

}
