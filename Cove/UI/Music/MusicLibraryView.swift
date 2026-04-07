import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct MusicLibraryView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let library {
                    // MARK: - Discovery Shelves

                    MusicDiscoveryShelf(
                        title: "Recently Added",
                        sortField: .dateCreated,
                        library: library
                    )

                    MusicDiscoveryShelf(
                        title: "Most Played",
                        sortField: .playCount,
                        library: library
                    )

                    MusicDiscoveryShelf(
                        title: "Recently Played",
                        sortField: .datePlayed,
                        library: library
                    )

                    // MARK: - Artists

                    ArtistsShelfSection(library: library)

                    // MARK: - Albums

                    AlbumsGridSection(library: library)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Music")
    }
}

// MARK: - Artists Shelf Section

/// Loads a limited set of artists and displays them in a horizontal scroll.
/// A "See All" link navigates to the full paginated `ArtistListView`.
private struct ArtistsShelfSection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var artists: [MediaItem] = []
    @State private var isLoading = true

    private let limit = 20

    var body: some View {
        if isLoading || !artists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Artists")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    NavigationLink {
                        ArtistListView(library: library)
                            .navigationTitle("Artists")
                            #if os(iOS)
                                .navigationBarTitleDisplayMode(.large)
                            #endif
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)

                if isLoading {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                ArtistShelfPlaceholder()
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(artists) { artist in
                                NavigationLink(value: artist) {
                                    ArtistShelfCard(
                                        name: artist.title,
                                        imageURL: imageURL(for: artist)
                                    )
                                }
                                .buttonStyle(.plain)
                                .artistContextMenu(artist: artist)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .task(id: library.id) {
                await loadArtists()
            }
        }
    }

    private func loadArtists() async {
        let provider = appState.provider

        do {
            let sort = SortOptions(field: .name, order: .ascending)
            let filter = FilterOptions(
                limit: limit,
                includeItemTypes: ["MusicArtist"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            artists = result.items
        } catch {
            artists = []
        }
        isLoading = false
    }

    private func imageURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 240, height: 240)
        )
    }
}

// MARK: - Artist Shelf Card

private struct ArtistShelfCard: View {
    let name: String
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 8) {
            MediaImage.artwork(url: imageURL, cornerRadius: .infinity)
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(width: 120)
        }
    }
}

private struct ArtistShelfPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.quaternary)
                .frame(width: 120, height: 120)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 80, height: 12)
        }
    }
}

// MARK: - Albums Grid Section

/// Loads a limited set of albums and displays them in a vertical grid.
/// A "See All" link navigates to the full paginated `AlbumListView`.
private struct AlbumsGridSection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var albums: [MediaItem] = []
    @State private var isLoading = true

    private let limit = 20
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Albums")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                NavigationLink {
                    AlbumListView(library: library)
                        .navigationTitle("Albums")
                        #if os(iOS)
                            .navigationBarTitleDisplayMode(.large)
                        #endif
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal)

            if isLoading {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<6, id: \.self) { _ in
                        AlbumGridPlaceholder()
                    }
                }
                .padding(.horizontal)
            } else if albums.isEmpty {
                Text("No albums found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumGridCard(
                                title: album.title,
                                imageURL: imageURL(for: album)
                            )
                        }
                        .buttonStyle(.plain)
                        .albumContextMenu(album: album)
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: library.id) {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        let provider = appState.provider

        do {
            let sort = SortOptions(field: .dateCreated, order: .descending)
            let filter = FilterOptions(
                limit: limit,
                includeItemTypes: ["MusicAlbum"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            albums = result.items
        } catch {
            albums = []
        }
        isLoading = false
    }

    private func imageURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Album Grid Card

private struct AlbumGridCard: View {
    let title: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
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

private struct AlbumGridPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fill)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MusicLibraryView(library: nil)
            .environment(AppState())
    }
}
