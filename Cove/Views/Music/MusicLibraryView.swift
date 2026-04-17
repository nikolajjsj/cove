import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct MusicLibraryView: View {
    let library: MediaLibrary?
    @Default(.musicSections) private var sections
    @State private var showCustomization = false
    @State private var hasMigratedSections = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let library {
                    ForEach(visibleSections, id: \.section) { config in
                        sectionView(for: config.section, library: library)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Music")
        .onAppear {
            guard !hasMigratedSections else { return }
            hasMigratedSections = true
            sections.migrateMissingSections()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Customize", systemImage: "slider.horizontal.3") {
                    showCustomization = true
                }
            }
        }
        .sheet(isPresented: $showCustomization) {
            MusicCustomizationSheet()
        }
    }

    // MARK: - Helpers

    private var visibleSections: [SectionConfig<MusicSection>] {
        sections.filter(\.isVisible)
    }

    @ViewBuilder
    private func sectionView(for section: MusicSection, library: MediaLibrary) -> some View {
        switch section {
        case .recentlyPlayed:
            RecentlyPlayedSongsSection(library: library)

        case .recentlyAdded:
            MusicDiscoveryShelf(
                title: "Recently Added",
                sortField: .dateCreated,
                library: library
            )

        case .smartPlaylists:
            SmartPlaylistsSection()

        case .mostPlayed:
            MusicDiscoveryShelf(
                title: "Most Played",
                sortField: .playCount,
                library: library
            )

        case .artists:
            ArtistsShelfSection(library: library)

        case .genres:
            MusicGenresShelfSection(library: library)

        case .playlists:
            PlaylistsShelfSection()

        case .albums:
            AlbumsGridSection(library: library)
        }
    }
}

// MARK: - Recently Played Songs Section

/// Loads recently played songs and displays them as horizontally scrolling cards.
private struct RecentlyPlayedSongsSection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    private let limit = 20

    var body: some View {
        if loader.isLoading || !loader.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recently Played")
                    .font(.title2)
                    .bold()
                    .padding(.horizontal)

                if loader.isLoading {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonCard.song
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(loader.items.enumerated(), id: \.element.id) {
                                index,
                                song in
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
                    .scrollIndicators(.hidden)
                }
            }
            .task(id: library.id) {
                await loader.load {
                    let sort = SortOptions(field: .datePlayed, order: .descending)
                    let filter = FilterOptions(
                        limit: limit,
                        includeItemTypes: ["Audio"]
                    )
                    let result = try await authManager.provider.pagedItems(
                        in: library, sort: sort, filter: filter
                    )
                    return result.items
                }
            }
        }
    }

    private func playSong(at index: Int) {
        let tracks = loader.items.map { item in
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
        authManager.provider.imageURL(
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
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    private let limit = 20

    var body: some View {
        if loader.isLoading || !loader.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Artists")
                        .font(.title2)
                        .bold()

                    Spacer()

                    NavigationLink(value: MusicBrowseRoute.allArtists(libraryId: library.id)) {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)

                if loader.isLoading {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonCard.artist
                                    .frame(width: 120)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 14) {
                            ForEach(loader.items) { artist in
                                ArtistCard(item: artist, imageURL: imageURL(for: artist))
                                    .frame(width: 120)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .task(id: library.id) {
                await loader.load {
                    let sort = SortOptions(field: .name, order: .ascending)
                    let filter = FilterOptions(
                        limit: limit,
                        includeItemTypes: ["MusicArtist"]
                    )
                    let result = try await authManager.provider.pagedItems(
                        in: library, sort: sort, filter: filter
                    )
                    return result.items
                }
            }
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 240, height: 240)
        )
    }
}

// MARK: - Music Genres Shelf Section

/// Loads music genres for the current library and displays them as
/// gradient cards in a horizontal scroll rail, matching the visual
/// language of the video genre section on the home screen.
/// A "See All" link navigates to the full genre list via `MusicBrowseRoute`.
private struct MusicGenresShelfSection: View {
    let library: MediaLibrary
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    var body: some View {
        if loader.isLoading || !loader.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Genres")
                        .font(.title2)
                        .bold()

                    Spacer()

                    NavigationLink(value: MusicBrowseRoute.allGenres(libraryId: library.id)) {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(loader.items) { genre in
                            NavigationLink(value: genre) {
                                GenreCard(
                                    name: genre.title,
                                    icon: MusicGenreIconMap.icon(for: genre.title)
                                )
                            }
                            .buttonStyle(MusicGenreCardButtonStyle())
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .task(id: library.id) {
                await loader.load {
                    try await authManager.provider.genres(in: library)
                }
            }
        }
    }
}

/// Spring-scale press effect for music genre cards.
private struct MusicGenreCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - Playlists Shelf Section

/// Loads the user's playlists and displays them in a horizontal shelf.
/// A "See All" link navigates to the full playlist list via `MusicBrowseRoute`.
private struct PlaylistsShelfSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<Playlist>()

    private let limit = 20

    var body: some View {
        if loader.isLoading || !loader.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Playlists")
                        .font(.title2)
                        .bold()

                    Spacer()

                    NavigationLink(value: MusicBrowseRoute.allPlaylists) {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)

                if loader.isLoading {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonCard.albumShelf()
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(loader.items) { playlist in
                                PlaylistCard(playlist: playlist, imageURL: imageURL(for: playlist))
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .task {
                await loader.load {
                    let all = try await authManager.provider.playlists()
                    return Array(all.prefix(limit))
                }
            }
        }
    }

    private func imageURL(for playlist: Playlist) -> URL? {
        authManager.provider.imageURL(
            for: playlist.id,
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
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()

    private let limit = 20
    @Default(.gridDensity) private var gridDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Albums")
                    .font(.title2)
                    .bold()

                Spacer()

                NavigationLink(value: MusicBrowseRoute.allAlbums(libraryId: library.id)) {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal)

            if loader.isLoading {
                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonCard.albumGrid
                    }
                }
                .padding(.horizontal)
            } else if loader.items.isEmpty {
                Text("No albums found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(loader.items) { album in
                        AlbumCard(item: album, imageURL: imageURL(for: album))
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: library.id) {
            await loader.load {
                let sort = SortOptions(field: .dateCreated, order: .descending)
                let filter = FilterOptions(
                    limit: limit,
                    includeItemTypes: ["MusicAlbum"]
                )
                let result = try await authManager.provider.pagedItems(
                    in: library, sort: sort, filter: filter
                )
                return result.items
            }
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Preview

#Preview {
    let state = AppState.preview
    NavigationStack {
        MusicLibraryView(library: nil)
            .environment(state)
            .environment(state.authManager)
    }
}
