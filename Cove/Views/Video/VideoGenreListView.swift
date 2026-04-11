import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct VideoGenreListView: View {
    let library: MediaLibrary?
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220))
    ]

    var body: some View {
        Group {
            if searchText.isEmpty {
                mainContent
            } else {
                filteredContent
            }
        }
        .navigationTitle("Genres")
        .largeNavigationTitle()
        .searchable(text: $searchText, prompt: "Filter genres…")
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
                systemImage: "film.stack",
                description: Text("This library doesn't contain any genres yet.")
            )
        case .loaded:
            genreGrid(items: loader.items)
        }
    }

    // MARK: - Filtered Content

    @ViewBuilder
    private var filteredContent: some View {
        let filtered = loader.items.filter { $0.title.localizedStandardContains(searchText) }
        if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            genreGrid(items: filtered)
        }
    }

    // MARK: - Genre Grid

    private func genreGrid(items: [MediaItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { genre in
                    NavigationLink(
                        value: VideoGenreRoute(genre: genre.title, libraryId: library?.id)
                    ) {
                        GenreCapsuleCard(name: genre.title)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - Data Loading

    private func loadGenres() async {
        guard let library else {
            loader.fail("No library available.")
            return
        }

        let provider = authManager.provider

        await loader.load {
            try await provider.genres(in: library)
        }
    }
}

// MARK: - Genre Capsule Card

private struct GenreCapsuleCard: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
            )
            .clipShape(.rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        VideoGenreListView(library: nil)
            .environment(AuthManager(serverRepository: nil))
    }
}
