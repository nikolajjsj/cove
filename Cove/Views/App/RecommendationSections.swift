import JellyfinProvider
import Models
import Persistence
import SwiftUI

// MARK: - Because You Watched Section

/// Picks the most recently watched item from resume history, then fetches
/// similar items via `/Items/{id}/Similar`. The section title dynamically
/// includes the source item's name (e.g. "Because You Watched Breaking Bad").
struct BecauseYouWatchedSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppState.self) private var appState
    @State private var sourceTitle: String?

    var body: some View {
        // Read the provider on the main actor; the fetch closure is @Sendable and
        // cannot reach main-actor state itself.
        let provider = authManager.provider
        let appState = appState

        ContentRail(
            cardWidth: { _ in 130 },
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            // The seed comes from the local Resume feed when possible; the
            // similar-items lookup is server-side by nature and stays there.
            let resumeItems: [MediaItem]
            if let local = await appState.localCatalog() {
                resumeItems = try await local.repository.resumeItems(scope: local.scope, limit: 1)
            } else {
                resumeItems = try await provider.resumeItems()
            }

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
    @Environment(AppState.self) private var appState

    var body: some View {
        let provider = authManager.provider
        let appState = appState
        ContentRail(
            title: "Recently Added",
            cardWidth: { _ in 130 },
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            if let local = await appState.localCatalog() {
                return try await local.repository.recentlyAdded(scope: local.scope)
            }
            return try await provider.recentlyAdded()
        } card: { item in
            MediaCard(item: item)
        }
    }
}
