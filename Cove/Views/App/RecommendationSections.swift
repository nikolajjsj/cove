import JellyfinProvider
import Models
import SwiftUI

// MARK: - Because You Watched Section

/// Picks the most recently watched item from resume history, then fetches
/// similar items via `/Items/{id}/Similar`. The section title dynamically
/// includes the source item's name (e.g. "Because You Watched Breaking Bad").
struct BecauseYouWatchedSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var sourceTitle: String?

    var body: some View {
        ContentRail(
            cardWidth: { _ in 130 },
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            let provider = authManager.provider
            let resumeItems = try await provider.resumeItems()

            guard let source = resumeItems.first else { return [] }

            // Publish the source title back to the main actor for the header
            await MainActor.run { sourceTitle = source.seriesName ?? source.title }

            return try await provider.similarItems(for: source, limit: 20)
        } card: { item in
            MediaCard(item: item)
        } header: {
            SectionHeader(title: "Because You Watched \(sourceTitle ?? "…")")
        }
    }
}

// MARK: - Recently Added Section

/// Cross-library "recently added" content, sorted by date created.
/// Only Movies and Series are requested so episodes are naturally
/// collapsed into their parent series.
struct RecentlyAddedSection: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ContentRail(
            title: "Recently Added",
            cardWidth: { _ in 130 },
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            try await authManager.provider.recentlyAdded()
        } card: { item in
            MediaCard(item: item)
        }
    }
}
