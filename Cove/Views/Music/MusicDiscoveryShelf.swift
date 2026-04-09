import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct MusicDiscoveryShelf: View {
    let title: String
    let sortField: SortField
    let library: MediaLibrary
    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private let limit = 20

    var body: some View {
        if isLoading || !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                if isLoading {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonCard.albumShelf()
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { item in
                                AlbumCard(item: item, imageURL: imageURL(for: item))
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .task(id: library.id) {
                await loadItems()
            }
        }
    }

    // MARK: - Loading

    private func loadItems() async {
        let provider = authManager.provider

        do {
            let sort = SortOptions(field: sortField, order: .descending)
            let filter = FilterOptions(
                limit: limit,
                includeItemTypes: ["MusicAlbum"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            items = result.items
        } catch {
            items = []
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 240, height: 240)
        )
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: 24) {
                MusicDiscoveryShelf(
                    title: "Recently Added",
                    sortField: .dateCreated,
                    library: MediaLibrary(
                        id: ItemID("preview"), name: "Music", collectionType: .music)
                )
            }
        }
        .environment(AuthManager(serverRepository: nil))
    }
}
