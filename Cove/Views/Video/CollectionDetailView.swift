import CoveUI
import DataLoading
import ImageService
import JellyfinProvider
import Models
import SwiftUI

/// Detail view for a collection (boxset) showing a hero header and a grid of the movies inside.
struct CollectionDetailView: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var loader = CollectionLoader<MediaItem>()

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Backdrop

                heroSection

                // MARK: - Content beneath the hero

                VStack(alignment: .leading, spacing: 20) {
                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        ExpandableOverview(text: overview, lineLimit: 3)
                    }

                    // Metadata pills
                    metadataPills

                    // Items in collection
                    collectionItemsSection
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(item.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loader.load {
                try await authManager.provider.collectionItems(collectionId: item.id)
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HeroSection(imageURL: backdropURL, fallbackImageURL: primaryURL, aspectRatio: 16.0 / 9.0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.primary)

                if !loader.items.isEmpty {
                    Text(
                        "\(loader.items.count) \(loader.items.count == 1 ? "item" : "items")"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Metadata Pills

    @ViewBuilder
    private var metadataPills: some View {
        MetadataPillsView(buildMetadataPills())
    }

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

    // MARK: - Collection Items Grid

    @ViewBuilder
    private var collectionItemsSection: some View {
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
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { collectionItem in
                        NavigationLink(value: collectionItem) {
                            LibraryItemCard(item: collectionItem)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

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
