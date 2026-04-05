import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct AlbumListView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var albums: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading albums…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Albums",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if albums.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Your music library doesn't contain any albums yet.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(
                                    title: album.title,
                                    imageURL: imageURL(for: album)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: library?.id) {
            await loadAlbums()
        }
    }

    // MARK: - Data Loading

    private func loadAlbums() async {
        guard let library else {
            isLoading = false
            errorMessage = "No music library available."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions()
            let items = try await appState.provider.items(
                in: library,
                sort: sort,
                filter: filter
            )
            albums = items.filter { $0.mediaType == .album }
        } catch {
            errorMessage = error.localizedDescription
            albums = []
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Album Card

private struct AlbumCard: View {
    let title: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyImage(url: imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay { ProgressView() }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        AlbumListView(library: nil)
            .environment(AppState())
    }
}
