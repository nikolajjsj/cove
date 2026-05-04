import DataLoading
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct StudioListView: View {
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
        .navigationTitle("Studios")
        .largeNavigationTitle()
        .searchable(text: $searchText, prompt: "Filter studios…")
        .task(id: library?.id) { await loadStudios() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading studios…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Studios",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Studios",
                systemImage: "film.stack",
                description: Text("This library doesn't contain any studios.")
            )
        case .loaded:
            studioGrid(items: loader.items)
        }
    }

    // MARK: - Filtered Content

    @ViewBuilder
    private var filteredContent: some View {
        let filtered = loader.items.filter { $0.title.localizedStandardContains(searchText) }
        if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            studioGrid(items: filtered)
        }
    }

    // MARK: - Studio Grid

    private func studioGrid(items: [MediaItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { studio in
                    NavigationLink(
                        value: StudioRoute(studio: studio.title, libraryId: library?.id)
                    ) {
                        GenreCapsuleCard(name: studio.title)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - Data Loading

    private func loadStudios() async {
        guard let library else {
            loader.fail("No library available.")
            return
        }

        let provider = authManager.provider

        await loader.load {
            try await provider.studios(in: library)
        }
    }
}

// MARK: - Studio Capsule Card

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
            .background(.quaternary, in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        StudioListView(library: nil)
            .environment(AuthManager(serverRepository: nil))
    }
}
