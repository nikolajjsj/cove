import DataLoading
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import NukeUI
import SwiftUI

struct ArtistDetailView: View {
    let artistItem: MediaItem
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<Album>()

    @Default(.gridDensity) private var gridDensity

    var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView("Loading artist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "Unable to Load Artist",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .empty, .loaded:
                ScrollView {
                    VStack(spacing: 24) {
                        ArtistHeaderView(artistItem: artistItem, imageURL: artistImageURL)
                        ArtistAlbumsSection(albums: loader.items)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(artistItem.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavoriteToggle(itemId: artistItem.id, userData: artistItem.userData)
            }
        }
        .task {
            await loader.load {
                try await authManager.provider.albums(artist: artistItem.id)
            }
        }
    }

    // MARK: - Image Helpers

    private var artistImageURL: URL? {
        authManager.provider.imageURL(
            for: artistItem,
            type: .primary,
            maxSize: CGSize(width: 400, height: 400)
        )
    }
}

// MARK: - Artist Header View

private struct ArtistHeaderView: View {
    let artistItem: MediaItem
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            // Artist image (circular)
            MediaImage(
                url: imageURL,
                placeholderIcon: "music.mic",
                placeholderIconFont: .system(size: 48),
                cornerRadius: .infinity
            )
            .frame(width: 200, height: 200)

            // Artist name
            Text(artistItem.title)
                .font(.title)
                .bold()
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
}

// MARK: - Artist Albums Section

private struct ArtistAlbumsSection: View {
    let albums: [Album]
    @Environment(AuthManager.self) private var authManager
    @Default(.gridDensity) private var gridDensity

    var body: some View {
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

                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(albums) { album in
                        AlbumCard(
                            album: album,
                            subtitle: [album.year.map { String($0) }, album.genre]
                                .compactMap { $0 }
                                .joined(separator: " · "),
                            imageURL: albumImageURL(for: album.id)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func albumImageURL(for itemId: ItemID) -> URL? {
        authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 300, height: 300))
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        ArtistDetailView(
            artistItem: MediaItem(
                id: ItemID("preview-artist"),
                title: "Preview Artist",
                overview: "A talented musician with many albums.",
                mediaType: .artist
            )
        )
        .environment(state)
        .environment(state.authManager)
    }
}
