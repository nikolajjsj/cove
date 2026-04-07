import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Continue Watching section
                ContinueWatchingSection()

                if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No libraries found on this server.")
                    )
                } else {
                    ForEach(appState.libraries) { library in
                        LibrarySection(library: library)
                    }
                }
            }
            .padding()
        }

    }

}

// MARK: - Continue Watching Section

private struct ContinueWatchingSection: View {
    @Environment(AppState.self) private var appState
    @State private var resumeItems: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if !resumeItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Continue Watching")
                        .font(.title2)
                        .fontWeight(.bold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(resumeItems) { item in
                                NavigationLink(value: item) {
                                    ContinueWatchingCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadResumeItems()
        }
    }

    private func loadResumeItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            resumeItems = try await appState.provider.resumeItems()
        } catch {
            resumeItems = []
        }
    }
}

// MARK: - Continue Watching Card

private struct ContinueWatchingCard: View {
    let item: MediaItem
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop/thumbnail image (landscape)
                MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 8)
                    .frame(width: 240)

                // Progress bar
                if let progress = watchProgress, progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * progress, height: 4)
                            }
                        }
                    }
                    .frame(width: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(8)
            }

            // Title
            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            // Remaining time
            if let remaining = remainingTimeText {
                Text(remaining)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 240)
    }

    // MARK: - Helpers

    private var thumbnailURL: URL? {
        // Try backdrop first for landscape, fall back to primary
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 480, height: 270)
        )
            ?? appState.provider.imageURL(
                for: item,
                type: .primary,
                maxSize: CGSize(width: 480, height: 270)
            )
    }

    private var watchProgress: Double? {
        guard let position = item.userData?.playbackPosition, position > 0 else { return nil }
        // We don't have total duration on MediaItem, so estimate from position
        // If we have a rough guess, show something. Otherwise just show a small indicator.
        // For now, just return a small value to indicate "in progress"
        // The real progress would need runtime from the full item
        return min(max(position / max(position * 2.5, 1), 0.05), 0.95)
    }

    private var remainingTimeText: String? {
        guard let position = item.userData?.playbackPosition, position > 0 else { return nil }
        let positionMinutes = Int(position) / 60
        if positionMinutes > 0 {
            return "\(positionMinutes) min watched"
        }
        return nil
    }

    private var placeholderIcon: String {
        switch item.mediaType {
        case .movie: return "film"
        case .episode: return "play.rectangle"
        case .series: return "tv"
        default: return "play.rectangle"
        }
    }
}

// MARK: - Library Section (horizontal scroll of recent items)

private struct LibrarySection: View {
    let library: MediaLibrary
    @Environment(AppState.self) private var appState
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: library) {
                HStack {
                    Text(library.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !isLoading && items.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        if isLoading {
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonCard(
                                    width: defaultCardWidth,
                                    aspectRatio: defaultAspectRatio,
                                    lineCount: 2
                                )
                            }
                        } else {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    LibraryItemCard(item: item)
                                        .frame(width: cardWidth(for: item))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        let firstVisit = items.isEmpty
        
        if firstVisit { isLoading = true }
        defer { if firstVisit { isLoading = false } }
        do {
            let sort = SortOptions(field: .dateAdded, order: .descending)
            let filter = FilterOptions(
                limit: 20,
                includeItemTypes: library.includeItemTypes,
            )
            items = try await appState.provider.items(in: library, sort: sort, filter: filter)
        } catch {
            items = []
        }
    }

    private var isMusic: Bool {
        library.collectionType == .music
    }

    private var defaultCardWidth: CGFloat {
        isMusic ? 140 : 130
    }

    private var defaultAspectRatio: CGFloat {
        isMusic ? 1.0 : 2.0 / 3.0
    }

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist:
            140  // Square cards for music
        default:
            130  // Portrait cards for video
        }
    }
}
