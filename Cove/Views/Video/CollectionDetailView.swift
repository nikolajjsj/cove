import CoveUI
import DataLoading
import Defaults
import ImageService
import JellyfinProvider
import Models
import SwiftUI

/// Detail view for a collection (boxset) showing a hero header and a grid of the movies inside.
struct CollectionDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var loader = CollectionLoader<MediaItem>()
    @State private var detailLoader = DetailItemLoader()

    @Default(.gridDensity) private var gridDensity

    /// The fully-fetched item (with people, genres, studios, etc.),
    /// falling back to the navigation item.
    private var displayItem: MediaItem {
        detailLoader.displayItem(fallback: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Backdrop

                CollectionHeroSection(
                    item: item,
                    backdropURL: backdropURL,
                    primaryURL: primaryURL,
                    itemCount: loader.items.count
                )

                // MARK: - Content beneath the hero

                VStack(alignment: .leading, spacing: 20) {
                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        ExpandableOverview(text: overview, lineLimit: 3)
                            .padding(.horizontal)
                    }

                    // Metadata pills
                    CollectionMetadataPills(pills: buildMetadataPills())
                        .padding(.horizontal)

                    // External Links
                    if let providerIds = displayItem.providerIds,
                        providerIds.hasAny
                    {
                        ExternalLinksSection(
                            providerIds: providerIds,
                            mediaType: item.mediaType
                        )
                        .padding(.horizontal)
                    }

                    // Genres
                    if let genres = displayItem.genres ?? item.genres, !genres.isEmpty {
                        TappableChipFlowSection(
                            title: "Genres",
                            items: genres,
                            libraryId: nil
                        )
                        .padding(.horizontal)
                    }

                    // Studios
                    if let studios = displayItem.studios, !studios.isEmpty {
                        ChipFlowSection(title: "Studios", items: studios)
                            .padding(.horizontal)
                    }

                    // Items in collection
                    CollectionItemsSection(loader: loader)
                        .padding(.horizontal)

                    // Cast & Crew (horizontal scroll — no padding)
                    if !displayItem.people.isEmpty {
                        CastCrewRail(people: displayItem.people)
                    }

                    // More Like This (horizontal scroll — no padding)
                    MediaItemRail(title: "More Like This") { [item] in
                        try await authManager.provider.similarItems(for: item, limit: 12)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(item.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .inlineNavigationTitle()
        .task {
            await detailLoader.load {
                try await authManager.provider.item(id: item.id)
            }
        }
        .task {
            await loader.load {
                try await authManager.provider.collectionItems(collectionId: item.id)
            }
        }
    }

    // MARK: - Metadata Pills (builder)

    private func buildMetadataPills() -> [MetadataPill] {
        var pills: [MetadataPill] = []

        if let pill = MetadataPill.communityRating(item.communityRating ?? 0) {
            pills.append(pill)
        }

        if let pill = MetadataPill.criticRating(item.criticRating ?? 0) {
            pills.append(pill)
        }

        if !loader.items.isEmpty {
            pills.append(.itemCount(loader.items.count))
        }

        return pills
    }

}

// MARK: - Hero Section

private struct CollectionHeroSection: View {
    let item: MediaItem
    let backdropURL: URL?
    let primaryURL: URL?
    let itemCount: Int

    var body: some View {
        HeroSection(imageURL: backdropURL, fallbackImageURL: primaryURL, aspectRatio: 16.0 / 9.0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.primary)

                if itemCount > 0 {
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Metadata Pills

private struct CollectionMetadataPills: View {
    let pills: [MetadataPill]

    var body: some View {
        MetadataPillsView(pills)
    }
}

// MARK: - Collection Items Grid

private struct CollectionItemsSection: View {
    let loader: CollectionLoader<MediaItem>

    @Default(.gridDensity) private var gridDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In This Collection")
                .font(.title3.weight(.bold))

            switch loader.phase {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("Loading…")
                    Spacer()
                }
                .padding(.vertical, 32)
            case .failed(let message):
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .padding(.vertical, 16)
            case .empty:
                ContentUnavailableView(
                    "No Items",
                    systemImage: "rectangle.stack",
                    description: Text("This collection appears to be empty.")
                )
                .padding(.vertical, 16)
            case .loaded(let items):
                LazyVGrid(columns: gridDensity.columns, spacing: gridDensity.gridSpacing) {
                    ForEach(items) { collectionItem in
                        NavigationLink(value: collectionItem) {
                            MediaCard(item: collectionItem)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

extension CollectionDetailView {
    // MARK: - Image Helpers

    private var backdropURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private var primaryURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 600, height: 900)
        )
    }
}
