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
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                LazyImage(url: backdropURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if state.isLoading {
                        Rectangle()
                            .fill(.black)
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    } else {
                        // Fallback: try primary image
                        LazyImage(url: primaryURL) { primaryState in
                            if let image = primaryState.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                LinearGradient(
                                    colors: [
                                        .blue.opacity(0.3),
                                        .purple.opacity(0.2),
                                        .black.opacity(0.8),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        }
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                // Gradient scrim at the bottom for text legibility
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: Color(.systemBackground).opacity(0.6), location: 0.65),
                        .init(color: Color(.systemBackground), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
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
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
    }

    // MARK: - Metadata Pills

    @ViewBuilder
    private var metadataPills: some View {
        let pills = buildMetadataPills()
        if !pills.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pills, id: \.label) { pill in
                        HStack(spacing: 4) {
                            if let icon = pill.icon {
                                Image(systemName: icon)
                                    .font(.caption2.weight(.semibold))
                            }
                            Text(pill.label)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(pill.tint ?? .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemFill))
                        )
                    }
                }
            }
        }
    }

    private struct MetadataPill: Hashable {
        let icon: String?
        let label: String
        let tint: Color?

        func hash(into hasher: inout Hasher) {
            hasher.combine(label)
        }
    }

    private func buildMetadataPills() -> [MetadataPill] {
        var pills: [MetadataPill] = []

        if let rating = item.communityRating, rating > 0 {
            let formatted =
                rating.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", rating)
                : String(format: "%.1f", rating)
            pills.append(MetadataPill(icon: "star.fill", label: formatted, tint: .yellow))
        }

        if let critic = item.criticRating, critic > 0 {
            pills.append(
                MetadataPill(
                    icon: "heart.fill", label: "\(Int(critic))%",
                    tint: critic >= 60 ? .green : .red))
        }

        if !collectionItems.isEmpty {
            pills.append(
                MetadataPill(
                    icon: "rectangle.stack.fill",
                    label:
                        "\(collectionItems.count) \(collectionItems.count == 1 ? "item" : "items")",
                    tint: nil
                )
            )
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
