import Models
import SwiftUI

struct AlbumListView: View {
    let library: MediaLibrary?
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false

    var body: some View {
        PagedMediaGridView(
            library: library,
            itemType: "MusicAlbum",
            sortField: sortField,
            sortOrder: sortOrder,
            isFavoriteFilter: isFavoriteFilter,
            emptyTitle: "No Albums",
            emptyIcon: "square.stack",
            emptyMessage: "Your music library doesn't contain any albums yet.",
            entityName: "album"
        ) { item, imageURL in
            AlbumCard(item: item, imageURL: imageURL)
        }
    }
}

#Preview {
    NavigationStack {
        AlbumListView(library: nil)
            .environment(AppState())
    }
}
