import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct MusicDiscoveryShelf: View {
    let title: String
    let sortField: SortField
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                ShelfPlaceholder()
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    ShelfCard(
                                        title: item.title,
                                        imageURL: imageURL(for: item)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .task(id: library.id) {
                await loadItems()
            }
        }
    }

    // MARK: - Loading

    private func loadItems() async {
        let provider = appState.provider

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
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 240, height: 240)
        )
    }
}

// MARK: - Shelf Card

private struct ShelfCard: View {
    let title: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
                .frame(width: 140, alignment: .leading)
        }
    }
}

// MARK: - Placeholder

private struct ShelfPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 140, height: 140)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 100, height: 12)
        }
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
        .environment(AppState())
    }
}
