import Models
import SwiftUI

struct ArtistListView: View {
    let library: MediaLibrary?
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false

    var body: some View {
        PagedMediaGridView(
            library: library,
            itemType: "MusicArtist",
            sortField: sortField,
            sortOrder: sortOrder,
            isFavoriteFilter: isFavoriteFilter,
            emptyTitle: "No Artists",
            emptyIcon: "music.mic",
            emptyMessage: "Your music library doesn't contain any artists yet.",
            entityName: "artist"
        ) { item, imageURL in
            ArtistCard(item: item, imageURL: imageURL)
        }
    }
}

#Preview {
    NavigationStack {
        ArtistListView(library: nil)
            .environment(AppState.preview)
    }
}
