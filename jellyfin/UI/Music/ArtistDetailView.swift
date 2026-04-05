import ImageService
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct ArtistDetailView: View {
    let artistItem: MediaItem
    @Environment(AppState.self) private var appState
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading artist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Artist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        artistHeader
                        albumsSection
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(artistItem.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(
                albumItem: MediaItem(
                    id: album.id,
                    title: album.title,
                    mediaType: .album
                )
            )
        }
        .task {
            await loadAlbums()
        }
    }

    // MARK: - Header

    private var artistHeader: some View {
        VStack(spacing: 16) {
            // Artist image (circular)
            LazyImage(url: artistImageURL) { state in
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
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            // Artist name
            Text(artistItem.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Overview
            if let overview = artistItem.overview, !overview.isEmpty {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    // MARK: - Albums Section

    @ViewBuilder
    private var albumsSection: some View {
        if albums.isEmpty {
            ContentUnavailableView(
                "No Albums",
                systemImage: "square.stack",
                description: Text("No albums found for this artist.")
            )
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Albums")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            ArtistAlbumCard(
                                album: album,
                                imageURL: albumImageURL(for: album.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Data Loading

    private func loadAlbums() async {
        isLoading = true
        errorMessage = nil
        do {
            albums = try await appState.provider.albums(artist: artistItem.id)
        } catch {
            errorMessage = error.localizedDescription
            albums = []
        }
        isLoading = false
    }

    // MARK: - Image Helpers

    private var artistImageURL: URL? {
        appState.provider.imageURL(
            for: artistItem,
            type: .primary,
            maxSize: CGSize(width: 400, height: 400)
        )
    }

    private func albumImageURL(for itemId: ItemID) -> URL? {
        let tempItem = MediaItem(id: itemId, title: "", mediaType: .album)
        return appState.provider.imageURL(
            for: tempItem,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Artist Album Card

private struct ArtistAlbumCard: View {
    let album: Album
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

            Text(album.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                if let year = album.year {
                    Text(String(year))
                }
                if album.year != nil, album.genre != nil {
                    Text("·")
                }
                if let genre = album.genre {
                    Text(genre)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        ArtistDetailView(
            artistItem: MediaItem(
                id: ItemID("preview-artist"),
                title: "Preview Artist",
                overview: "A talented musician with many albums.",
                mediaType: .artist
            )
        )
        .environment(AppState())
    }
}
