import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct MusicLibraryView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let library {
                    // MARK: - Recently Played Songs

                    RecentlyPlayedSongsSection(library: library)

                    // MARK: - Recently Added

                    MusicDiscoveryShelf(
                        title: "Recently Added",
                        sortField: .dateCreated,
                        library: library
                    )

                    // MARK: - Most Played

                    MusicDiscoveryShelf(
                        title: "Most Played",
                        sortField: .playCount,
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

// MARK: - Section Header

/// Reusable section header with a title and an optional "See All" navigation link.
private struct SectionHeader<Route: Hashable>: View {
    let title: String
    let route: Route?

    init(title: String, route: Route? = nil as MusicBrowseRoute?) {
        self.title = title
        self.route = route
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            if let route {
                NavigationLink(value: route) {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Recently Played Songs Section

/// Loads recently played songs and displays them as horizontally scrolling cards.
private struct RecentlyPlayedSongsSection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var songs: [MediaItem] = []
    @State private var isLoading = true

    private let limit = 20

    var body: some View {
        if isLoading || !songs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recently Played")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                if isLoading {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonCard.song
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                SongCard(
                                    item: song,
                                    subtitle: song.artistName ?? song.genres?.first,
                                    imageURL: imageURL(for: song)
                                ) {
                                    playSong(at: index)
                                }
                                .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .task(id: library.id) {
                await loadSongs()
            }
        }
    }

    private func loadSongs() async {
        let provider = appState.provider

        do {
            let sort = SortOptions(field: .datePlayed, order: .descending)
            let filter = FilterOptions(
                limit: limit,
                includeItemTypes: ["Audio"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            songs = result.items
        } catch {
            songs = []
        }
        isLoading = false
    }

    private func playSong(at index: Int) {
        let tracks = songs.map { item in
            Track(
                id: TrackID(item.id.rawValue),
                title: item.title,
                albumId: item.albumId.map { AlbumID($0.rawValue) },
                albumName: item.albumName,
                artistName: item.artistName,
                duration: item.runtime,
                userData: item.userData
            )
        }
        guard !tracks.isEmpty else { return }
        appState.audioPlayer.play(tracks: tracks, startingAt: index)
    }

    private func imageURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 240, height: 240)
        )
    }
}

// MARK: - Artists Shelf Section

/// Loads a limited set of artists and displays them in a horizontal scroll.
/// A "See All" link navigates via the centralized MusicBrowseRoute.
private struct ArtistsShelfSection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var artists: [MediaItem] = []
    @State private var isLoading = true

    private let limit = 20

    var body: some View {
        if isLoading || !artists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Artists",
                    route: MusicBrowseRoute.allArtists(libraryId: library.id)
                )

                if isLoading {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonCard.artist
                                    .frame(width: 120)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(artists) { artist in
                                ArtistCard(item: artist, imageURL: imageURL(for: artist))
                                    .frame(width: 120)
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

// MARK: - Albums Grid Section

/// Loads a limited set of albums and displays them in a vertical grid.
/// A "See All" link navigates via the centralized MusicBrowseRoute.
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
            SectionHeader(
                title: "Albums",
                route: MusicBrowseRoute.allAlbums(libraryId: library.id)
            )

            if isLoading {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonCard.albumGrid
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
                        AlbumCard(item: album, imageURL: imageURL(for: album))
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

// MARK: - Preview

#Preview {
    NavigationStack {
        MusicLibraryView(library: nil)
            .environment(AppState())
    }
}
