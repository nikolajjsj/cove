import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import NukeUI
import SwiftUI

struct ArtistDetailView: View {
    let artistItem: MediaItem
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<Album>()

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

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
        .task {
            await loader.load {
                try await authManager.provider.albums(artist: artistItem.id)
            }
        }
    }

    // MARK: - Header

    private var artistHeader: some View {
        VStack(spacing: 16) {
            // Artist image (circular)
            MediaImage(
                url: artistImageURL,
                placeholderIcon: "music.mic",
                placeholderIconFont: .system(size: 48),
                cornerRadius: .infinity
            )
            .frame(width: 200, height: 200)
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
        if loader.items.isEmpty {
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
                    ForEach(loader.items) { album in
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

    // MARK: - Image Helpers

    private var artistImageURL: URL? {
        authManager.provider.imageURL(
            for: artistItem,
            type: .primary,
            maxSize: CGSize(width: 400, height: 400)
        )
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
