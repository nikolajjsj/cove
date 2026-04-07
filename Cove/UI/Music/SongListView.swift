import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct SongListView: View {
    let library: MediaLibrary?
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = PagedCollectionLoader<MediaItem>()

    private let pageSize = 40

    var body: some View {
        Group {
            mainContent
        }
        .task(id: "\(library?.id.rawValue ?? "")-\(sortField)-\(sortOrder)-\(isFavoriteFilter)") {
            await loadFirstPage()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch loader.phase {
        case .loading:
            ProgressView("Loading songs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Load Songs",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No Songs",
                systemImage: "music.note",
                description: Text("Your music library doesn't contain any songs yet.")
            )
        case .loaded:
            scrollContent
        }
    }

    private var scrollContent: some View {
        List {
            ForEach(Array(loader.items.enumerated()), id: \.element.id) { index, item in
                SongRow(
                    item: item,
                    imageURL: imageURL(for: item),
                    isCurrentTrack: isCurrentTrack(item),
                    isPlaying: isCurrentTrack(item) && appState.audioPlayer.isPlaying
                ) {
                    playFromIndex(index)
                }
                .onAppear { loader.onItemAppeared(item) }
                .mediaContextMenu(item: item)
            }

            if loader.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            if !loader.items.isEmpty && !loader.hasMore && loader.totalCount > 0 {
                Text("\(loader.totalCount) \(loader.totalCount == 1 ? "song" : "songs")")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadFirstPage() async {
        guard let library else {
            loader.reset()
            return
        }

        let provider = authManager.provider

        await loader.loadFirstPage(pageSize: pageSize) { limit, startIndex in
            let sort = SortOptions(field: sortField, order: sortOrder)
            let filter = FilterOptions(
                isFavorite: isFavoriteFilter ? true : Optional<Bool>.none,
                limit: limit,
                startIndex: startIndex,
                includeItemTypes: ["Audio"]
            )
            let result = try await provider.pagedItems(
                in: library, sort: sort, filter: filter
            )
            return .init(items: result.items, totalCount: result.totalCount)
        }
    }

    // MARK: - Playback

    private func playFromIndex(_ index: Int) {
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

    private func isCurrentTrack(_ item: MediaItem) -> Bool {
        appState.audioPlayer.queue.currentTrack?.id.rawValue == item.id.rawValue
    }

    // MARK: - Helpers

    private func imageURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 80, height: 80)
        )
    }
}

// MARK: - Song Row

private struct SongRow: View {
    let item: MediaItem
    let imageURL: URL?
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                MediaImage.trackThumbnail(url: imageURL)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(isCurrentTrack ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if let genres = item.genres, let firstGenre = genres.first {
                        Text(firstGenre)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isCurrentTrack {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }

                if let runtime = item.runtime, runtime > 0 {
                    Text(TimeFormatting.trackTime(runtime))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let state = AppState.preview
    NavigationStack {
        SongListView(library: nil)
            .environment(state)
            .environment(state.authManager)
    }
}
