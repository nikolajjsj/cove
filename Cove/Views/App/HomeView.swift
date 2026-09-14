import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import Persistence
import PlaybackEngine
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Default(.homeSections) private var sections
    @State private var showCustomization = false
    @State private var hasMigratedSections = false

    var body: some View {
        ScrollView {
            // Zero spacing on purpose: each section brings its own bottom space
            // while visible, so a hidden rail stays mounted at zero height and
            // costs no gap. See ContentRail.sectionSpacing.
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.libraries.isEmpty, appState.libraryLoadFailed {
                    ServerUnavailableView()
                        .frame(maxWidth: .infinity)
                } else if appState.libraries.isEmpty, appState.catalogSyncStatus.isBusy {
                    ProgressView("Syncing your library…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if appState.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "folder",
                        description: Text("No movie or TV libraries found on this server.")
                    )
                    .padding(.horizontal)
                } else {
                    ForEach(visibleSections, id: \.section) { config in
                        sectionView(for: config.section)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            // A full reconcile; the rails re-query in place when it lands.
            await appState.retryLoadLibraries()
            await appState.refreshCatalog()
        }
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
            HomeCustomizationSheet()
        }
    }

    // MARK: - Helpers

    /// Vertical space between Home sections, applied by each visible section.
    static let sectionSpacing: CGFloat = 24

    private var visibleSections: [SectionConfig<HomeSection>] {
        sections.filter(\.isVisible)
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .heroBanner:
            HeroBannerView(sectionSpacing: Self.sectionSpacing)
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
    @Environment(AppState.self) private var appState

    var body: some View {
        let catalog = appState.catalog
        ContentRail(
            title: "Continue Watching",
            cardWidth: { _ in 240 },
            reloadKey: appState.catalogGeneration,
            sectionSpacing: HomeView.sectionSpacing,
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            guard let catalog else { return [] }
            return try await catalog.repository.resumeItems(scope: catalog.scope)
        } card: { item in
            MediaCard(item: item, style: .landscape)
        }
    }
}

// MARK: - Up Next Section

private struct UpNextSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState

    var body: some View {
        let catalog = appState.catalog
        ContentRail(
            title: "Up Next",
            cardWidth: { _ in 240 },
            reloadKey: appState.catalogGeneration,
            sectionSpacing: HomeView.sectionSpacing,
            skeleton: { SkeletonCard.landscape(width: 240) }
        ) {
            guard let catalog else { return [] }
            return try await catalog.repository.nextUp(scope: catalog.scope)
        } card: { item in
            MediaCard(item: item, style: .landscape)
        }
    }
}

// MARK: - Library Section (horizontal scroll of recent items)

private struct LibrarySection: View {
    let library: MediaLibrary
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState

    var body: some View {
        let catalog = appState.catalog
        let library = library
        ContentRail(
            skeletonCount: 6,
            cardWidth: cardWidth,
            reloadKey: appState.catalogGeneration,
            sectionSpacing: HomeView.sectionSpacing,
            skeleton: {
                SkeletonCard(
                    width: defaultCardWidth,
                    aspectRatio: defaultAspectRatio,
                    lineCount: 2
                )
            },
            fetch: {
                guard let catalog else { return [] }
                return try await catalog.repository.latest(
                    libraryId: library.id.rawValue, itemTypes: library.includeItemTypes,
                    scope: catalog.scope)
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

    private var defaultCardWidth: CGFloat { 130 }

    private var defaultAspectRatio: CGFloat { 2.0 / 3.0 }

    private func cardWidth(for item: MediaItem) -> CGFloat { 130 }
}
