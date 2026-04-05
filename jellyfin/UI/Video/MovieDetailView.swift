import DownloadManager
import ImageService
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

struct MovieDetailView: View {
    let item: MediaItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isOverviewExpanded = false

    private let overviewLineLimit = 4

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Backdrop

                heroSection

                // MARK: - Content beneath the hero

                VStack(alignment: .leading, spacing: 20) {
                    playButton

                    // Metadata pills row
                    metadataPills

                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }

                    // Genres
                    if let genres = item.genres, !genres.isEmpty {
                        genresTags(genres)
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let downloadManager = appState.downloadManager {
                    DownloadButton(
                        item: item,
                        serverId: appState.activeConnection?.id.uuidString ?? "",
                        downloadManager: downloadManager
                    ) {
                        try await appState.provider.downloadURL(for: item, profile: nil)
                    }
                }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        // Color.clear defines the layout size; the image fills it as
        // an overlay so its layout frame never exceeds the container.
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
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
            .clipped()
            .overlay(alignment: .bottom) {
                // Gradient scrim at the bottom for text legibility
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: Color(.systemBackground).opacity(0.6), location: 0.7),
                        .init(color: Color(.systemBackground), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                // Title + subtitle overlaid on the gradient
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(.title, design: .default, weight: .bold))
                        .foregroundStyle(.primary)

                    heroSubtitleLine
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
    }

    // MARK: - Hero Subtitle (year · rating · runtime)

    @ViewBuilder
    private var heroSubtitleLine: some View {
        let parts = heroSubtitleParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Text(part)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heroSubtitleParts: [String] {
        var parts: [String] = []

        if let year = item.productionYear {
            parts.append(String(year))
        }

        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }

        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        return parts
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

        if let userData = item.userData {
            if userData.isPlayed {
                pills.append(
                    MetadataPill(icon: "checkmark.circle.fill", label: "Played", tint: .green))
            }
            if userData.playCount > 1 {
                pills.append(
                    MetadataPill(
                        icon: "arrow.counterclockwise", label: "Played \(userData.playCount)×",
                        tint: nil))
            }
        }

        return pills
    }

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            coordinator.play(item: item, using: appState.provider)
        } label: {
            HStack(spacing: 8) {
                if coordinator.isLoadingItem(item.id) {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body)
                }
                Text(playButtonLabel)
                    .fontWeight(.semibold)
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(coordinator.isLoadingItem(item.id))
    }

    private var playButtonLabel: String {
        if let position = item.userData?.playbackPosition, position > 0 {
            return "Resume at \(TimeFormatting.playbackPosition(position))"
        }
        return "Play"
    }

    // MARK: - Overview

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

    // MARK: - Genre Tags

    @ViewBuilder
    private func genresTags(_ genres: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Genres")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
            }
        }
    }

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for genre tags)

/// A simple wrapping layout that arranges children horizontally and
/// wraps to the next line when the row runs out of space.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return ArrangeResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}
