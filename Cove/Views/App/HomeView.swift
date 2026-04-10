import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Default(.homeSections) private var sections
    @State private var refreshID = UUID()
    @State private var showCustomization = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No libraries found on this server.")
                    )
                } else {
                    ForEach(visibleSections, id: \.section) { config in
                        sectionView(for: config.section)
                    }
                }
            }
            .padding()
            .id(refreshID)
        }
        .refreshable {
            refreshID = UUID()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Customize", systemImage: "slider.horizontal.3") {
                    showCustomization = true
                }
            }
        }
        .sheet(isPresented: $showCustomization) {
            HomeCustomizationSheet()
        }
    }

    // MARK: - Helpers

    private var visibleSections: [HomeSectionConfig] {
        sections.filter(\.isVisible)
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .heroBanner:
            HeroBannerView()

        case .continueWatching:
            ContinueWatchingSection()

        case .upNext:
            UpNextSection()

        case .movies:
            if let movies = appState.libraries.first(where: { $0.collectionType == .movies }) {
                LibrarySection(library: movies)
            }

        case .tvShows:
            if let tvShows = appState.libraries.first(where: { $0.collectionType == .tvshows }) {
                LibrarySection(library: tvShows)
            }

        case .collections:
            if let collections = appState.libraries.first(where: { $0.collectionType == .boxsets })
            {
                LibrarySection(library: collections)
            }

        case .becauseYouWatched:
            BecauseYouWatchedSection()

        case .recentlyAdded:
            RecentlyAddedSection()
        }
    }
}

// MARK: - Continue Watching Section

private struct ContinueWatchingSection: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ContentRail(
            title: "Continue Watching",
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            try await authManager.provider.resumeItems()
        } card: { item in
            ContinueWatchingCard(item: item)
        }
    }
}

// MARK: - Up Next Section

private struct UpNextSection: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ContentRail(
            title: "Up Next",
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            try await authManager.provider.nextUp()
        } card: { item in
            UpNextCard(item: item)
        }
    }
}

// MARK: - Library Section (horizontal scroll of recent items)

private struct LibrarySection: View {
    let library: MediaLibrary
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ContentRail(
            skeletonCount: 6,
            cardWidth: cardWidth,
            skeleton: {
                SkeletonCard(
                    width: defaultCardWidth,
                    aspectRatio: defaultAspectRatio,
                    lineCount: 2
                )
            },
            fetch: {
                let sort = SortOptions(field: .dateAdded, order: .descending)
                let filter = FilterOptions(
                    limit: 20,
                    includeItemTypes: library.includeItemTypes
                )
                return try await authManager.provider.items(
                    in: library, sort: sort, filter: filter
                )
            },
            card: { item in
                LibraryItemCard(item: item)
            },
            header: {
                NavigationLink(value: library) {
                    HStack {
                        Text(library.name)
                            .font(.title2)
                            .bold()
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        )
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
