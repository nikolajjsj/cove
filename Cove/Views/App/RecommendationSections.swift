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
        let catalog = appState.catalog
        ContentRail(
            cardWidth: { _ in 130 },
            reloadKey: appState.catalogGeneration,
            sectionSpacing: HomeView.sectionSpacing,
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            // The seed is the local Resume feed; the similar-items lookup is a
            // server recommendation by nature and stays one.
            guard let catalog else { return [] }
            let resumeItems = try await catalog.repository.resumeItems(scope: catalog.scope, limit: 1)
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
        let catalog = appState.catalog
        ContentRail(
            title: "Recently Added",
            cardWidth: { _ in 130 },
            reloadKey: appState.catalogGeneration,
            sectionSpacing: HomeView.sectionSpacing,
            skeleton: { SkeletonCard(width: 130, aspectRatio: 2.0 / 3.0, lineCount: 2) }
        ) {
            guard let catalog else { return [] }
            return try await catalog.repository.recentlyAdded(scope: catalog.scope)
        } card: { item in
            MediaCard(item: item)
        }
    }
}
