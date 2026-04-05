import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct ArtistListView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var artists: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading artists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Artists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if artists.isEmpty {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "music.mic",
                    description: Text("Your music library doesn't contain any artists yet.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(artists) { artist in
                            NavigationLink(value: artist) {
                                ArtistCard(
                                    name: artist.title,
                                    imageURL: imageURL(for: artist)
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
            await loadArtists()
        }
    }

    // MARK: - Data Loading

    private func loadArtists() async {
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
            artists = items.filter { $0.mediaType == .artist }
        } catch {
            errorMessage = error.localizedDescription
            artists = []
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

// MARK: - Artist Card

private struct ArtistCard: View {
    let name: String
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 8) {
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
                            Image(systemName: "music.mic")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ArtistListView(library: nil)
            .environment(AppState())
    }
}
