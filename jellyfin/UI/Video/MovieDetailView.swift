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

    // How many lines before we truncate and show "Show More"
    private let overviewLineLimit = 4

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Backdrop + Poster

                backdropSection

                // MARK: - Content

                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(item.title)
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    // Metadata line
                    metadataLine

                    // Play / Resume button
                    playButton

                    // Overview
                    if let overview = item.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(item.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
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

    // MARK: - Backdrop Section

    @ViewBuilder
    private var backdropSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            LazyImage(url: backdropURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                } else if state.isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .overlay { ProgressView() }
                } else {
                    // Gradient placeholder when no backdrop
                    LinearGradient(
                        colors: [.blue.opacity(0.4), .purple.opacity(0.3), .black.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .aspectRatio(16 / 9, contentMode: .fill)
                }
            }
            .clipped()

            // Bottom gradient fade for readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.bottom, 40)  // Account for poster overflow
    }

    // MARK: - Metadata Line

    @ViewBuilder
    private var metadataLine: some View {
        let parts = buildMetadataParts()
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func buildMetadataParts() -> [String] {
        var parts: [String] = []

        if let userData = item.userData {
            if userData.playbackPosition > 0 {
                // Show how far along the user is
                let position = userData.playbackPosition
                parts.append("\(TimeFormatting.duration(position)) watched")
            }
            if userData.isPlayed {
                parts.append("✓ Played")
            }
            if userData.playCount > 1 {
                parts.append("Played \(userData.playCount)×")
            }
        }

        return parts
    }

    // MARK: - Play Button

    @ViewBuilder
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
                }
                Text(playButtonLabel)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
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
            Text("Overview")
                .font(.headline)
                .foregroundStyle(.primary)

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

    // MARK: - Image Helpers

    private var backdropURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .backdrop,
            maxSize: CGSize(width: 1280, height: 720)
        )
    }

    private var posterURL: URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }
}
