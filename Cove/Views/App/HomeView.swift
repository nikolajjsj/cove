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
    @State private var hasMigratedSections = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No libraries found on this server.")
                    )
                    .padding(.horizontal)
                } else {
                    ForEach(visibleSections, id: \.section) { config in
                        sectionView(for: config.section)
                    }
                }
            }
            .padding(.vertical)
            .id(refreshID)
        }
        .refreshable {
            refreshID = UUID()
        }
        .onAppear {
            guard !hasMigratedSections else { return }
            hasMigratedSections = true
            migrateHomeSections()
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

    /// Appends any sections introduced since the user last launched the app.
    ///
    /// The `homeSections` preference is persisted, so `defaultSections` only
    /// applies on a completely fresh install. When a new section is added to
    /// `defaultSections`, existing users never see it because their stored
    /// array doesn't contain it. This migration inserts missing sections at
    /// the position they occupy in `defaultSections`, preserving the user's
    /// existing order and visibility settings for everything else.
    private func migrateHomeSections() {
        let existing = sections.map(\.section)
        let missing = HomeSectionConfig.defaultSections.filter { !existing.contains($0.section) }
        guard !missing.isEmpty else { return }

        for config in missing {
            // Find where this section lives in the default order and insert
            // it at the equivalent relative position in the user's array.
            guard
                let defaultIndex = HomeSectionConfig.defaultSections.firstIndex(
                    where: { $0.section == config.section })
            else {
                sections.append(config)
                continue
            }

            // Find the latest section before this one (in default order) that
            // the user already has, and insert after it.
            let precedingDefaults = HomeSectionConfig.defaultSections[..<defaultIndex]
                .map(\.section)
            if let insertAfter = sections.lastIndex(where: {
                precedingDefaults.contains($0.section)
            }) {
                sections.insert(config, at: sections.index(after: insertAfter))
            } else {
                sections.insert(config, at: sections.startIndex)
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .heroBanner:
            HeroBannerView()
                .padding(.horizontal)

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

        case .genres:
            GenresSection()

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
            cardWidth: { _ in 240 },
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            try await authManager.provider.resumeItems()
        } card: { item in
            MediaCard(item: item, style: .landscape)
        }
    }
}

// MARK: - Up Next Section

private struct UpNextSection: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ContentRail(
            title: "Up Next",
            cardWidth: { _ in 240 },
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            try await authManager.provider.nextUp()
        } card: { item in
            MediaCard(item: item, style: .landscape)
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
                MediaCard(item: item)
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
