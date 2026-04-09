import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct GenreListView: View {
    let library: MediaLibrary?
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    var body: some View {
        Group {
            mainContent
        }
        .task(id: library?.id) { await loadGenres() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading genres…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Genres",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Genres",
                systemImage: "guitars",
                description: Text("Your music library doesn't contain any genres yet.")
            )
        case .loaded:
            List(loader.items) { genre in
                NavigationLink(value: genre) {
                    GenreRow(name: genre.title)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Data Loading

    private func loadGenres() async {
        guard let library else {
            loader.fail("No music library available.")
            return
        }

        let provider = authManager.provider

        await loader.load {
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions(
                parentId: library.id,
                includeItemTypes: ["MusicGenre"]
            )
            return try await provider.items(in: library, sort: sort, filter: filter)
        }
    }
}

// MARK: - Genre Row

private struct GenreRow: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "guitars")
            .font(.body)
            .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        GenreListView(library: nil)
            .environment(AuthManager(serverRepository: nil))
    }
}
