import CoveUI
import ImageService
import JellyfinProvider
import Models
import SwiftUI

/// Detail view for a collection (boxset) showing a hero header and a grid of the movies inside.
struct CollectionDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var collectionItems: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                        overviewSection(overview)
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
            await loadCollectionItems()
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HeroSection(imageURL: backdropURL, fallbackImageURL: primaryURL, aspectRatio: 16.0 / 9.0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.primary)

                if !collectionItems.isEmpty {
                    Text(
                        "\(collectionItems.count) \(collectionItems.count == 1 ? "item" : "items")"
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

        if !collectionItems.isEmpty {
            pills.append(.itemCount(collectionItems.count))
        }

        return pills
    }

    // MARK: - Overview

    @State private var isOverviewExpanded = false
    private let overviewLineLimit = 3

    @ViewBuilder
    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(overview)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(isOverviewExpanded ? nil : overviewLineLimit)
                .animation(.easeInOut(duration: 0.25), value: isOverviewExpanded)

            Button {
                isOverviewExpanded.toggle()
            } label: {
                Text(isOverviewExpanded ? "Show Less" : "Show More")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: - Collection Items Grid

    @ViewBuilder
    private var collectionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In This Collection")
                .font(.title3.weight(.bold))

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading…")
                    Spacer()
                }
                .padding(.vertical, 32)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .padding(.vertical, 16)
            } else if collectionItems.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "rectangle.stack",
                    description: Text("This collection appears to be empty.")
                )
                .padding(.vertical, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(collectionItems) { collectionItem in
                        NavigationLink(value: collectionItem) {
                            LibraryItemCard(item: collectionItem)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadCollectionItems() async {
        isLoading = true
        errorMessage = nil

        do {
            collectionItems = try await appState.provider.collectionItems(collectionId: item.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private var primaryURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 600, height: 900)
        )
    }
}
