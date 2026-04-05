import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No libraries found on this server.")
                    )
                } else {
                    ForEach(appState.libraries) { library in
                        LibrarySection(library: library)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Library Section (horizontal scroll of recent items)

private struct LibrarySection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(library.name)
                .font(.title2)
                .fontWeight(.bold)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if items.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            LibraryItemCard(item: item)
                                .frame(width: cardWidth(for: item))
                        }
                    }
                }
            }
        }
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sort = SortOptions(field: .dateAdded, order: .descending)
            let filter = FilterOptions(limit: 20)
            items = try await appState.provider.items(in: library, sort: sort, filter: filter)
        } catch {
            items = []
        }
    }

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist:
            140  // Square cards for music
        default:
            130  // Portrait cards for video
        }
    }
}
