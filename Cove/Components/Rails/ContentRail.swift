import DataLoading
import Models
import SwiftUI

/// A generic, self-contained horizontal scroll rail that handles the full
/// fetch → skeleton → content (or hide-if-empty) lifecycle.
///
/// This is the primary building block for HomeView sections and detail-page
/// "related content" rails. You provide a header, a fetch closure, a skeleton,
/// and a card builder — the rail handles everything else:
///
/// - Skeleton placeholders while loading
/// - Stale-while-revalidate on re-appearance (via ``CollectionLoader``)
/// - Animated hide when the fetch returns empty or fails
/// - Cooperative cancellation when the view disappears
///
/// ```swift
/// ContentRail(
///     title: "Continue Watching",
///     skeleton: { SkeletonCard.landscape(width: 240) }
/// ) {
///     try await provider.resumeItems()
/// } card: { item in
///     ContinueWatchingCard(item: item)
/// }
/// ```
///
/// For rails that need a custom header (e.g. a navigable library title), use
/// the initializer that accepts a `@ViewBuilder header` closure.
struct ContentRail<Card: View, Skeleton: View, Header: View>: View {

    // MARK: - Configuration

    let fetch: @Sendable () async throws -> [MediaItem]
    @ViewBuilder let header: Header
    @ViewBuilder let skeleton: Skeleton
    @ViewBuilder let card: (MediaItem) -> Card

    let skeletonCount: Int
    let spacing: CGFloat
    let cardWidth: ((MediaItem) -> CGFloat)?

    // MARK: - State

    @State private var loader = CollectionLoader<MediaItem>()

    /// Controls the animated show/hide transition. Starts `true` and animates
    /// to `false` when the fetch returns empty or fails.
    @State private var isVisible = true

    // MARK: - Body

    var body: some View {
        if isVisible {
            Group {
                switch loader.phase {
                case .loading:
                    loadingContent

                case .loaded(let items):
                    loadedContent(items)

                case .empty, .failed:
                    // The loader resolved to empty/failed — animate out.
                    // We use `Color.clear` so SwiftUI has something to
                    // remove during the transition.
                    Color.clear
                        .frame(height: 0)
                        .onAppear { hideRail() }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: phaseKey)
            .task {
                await loader.load(fetch)
            }
        }
    }

    // MARK: - Loading State

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(0..<skeletonCount, id: \.self) { _ in
                        skeleton
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Loaded State

    private func loadedContent(_ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            if let cardWidth {
                                card(item)
                                    .frame(width: cardWidth(item))
                            } else {
                                card(item)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Helpers

    private func hideRail() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible = false
        }
    }

    /// A stable discriminator for animating phase transitions without
    /// re-triggering animations on every item change.
    private var phaseKey: String {
        switch loader.phase {
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        }
    }
}

// MARK: - Convenience: Simple Title Header

extension ContentRail where Header == SectionHeader {

    /// Creates a rail with a simple ``SectionHeader`` title.
    ///
    /// ```swift
    /// ContentRail(
    ///     title: "Up Next",
    ///     skeleton: { SkeletonCard.landscape(width: 240) }
    /// ) {
    ///     try await provider.nextUp()
    /// } card: { item in
    ///     UpNextCard(item: item)
    /// }
    /// ```
    init(
        title: String,
        skeletonCount: Int = 4,
        spacing: CGFloat = 12,
        cardWidth: ((MediaItem) -> CGFloat)? = nil,
        @ViewBuilder skeleton: @escaping () -> Skeleton,
        fetch: @escaping @Sendable () async throws -> [MediaItem],
        @ViewBuilder card: @escaping (MediaItem) -> Card
    ) {
        self.header = SectionHeader(title: title)
        self.skeleton = skeleton()
        self.skeletonCount = skeletonCount
        self.spacing = spacing
        self.cardWidth = cardWidth
        self.fetch = fetch
        self.card = card
    }
}

// MARK: - Convenience: Custom Header

extension ContentRail {

    /// Creates a rail with a fully custom header view.
    ///
    /// Use this when the header needs to be interactive (e.g. a `NavigationLink`
    /// to the full library):
    ///
    /// ```swift
    /// ContentRail(
    ///     skeletonCount: 6,
    ///     skeleton: { SkeletonCard.poster(width: 130) },
    ///     fetch: { try await provider.items(in: library, ...) },
    ///     card: { item in LibraryItemCard(item: item) },
    ///     header: {
    ///         NavigationLink(value: library) {
    ///             Text(library.name).font(.title2.bold())
    ///         }
    ///     }
    /// )
    /// ```
    init(
        skeletonCount: Int = 4,
        spacing: CGFloat = 12,
        cardWidth: ((MediaItem) -> CGFloat)? = nil,
        @ViewBuilder skeleton: @escaping () -> Skeleton,
        fetch: @escaping @Sendable () async throws -> [MediaItem],
        @ViewBuilder card: @escaping (MediaItem) -> Card,
        @ViewBuilder header: () -> Header
    ) {
        self.header = header()
        self.skeleton = skeleton()
        self.skeletonCount = skeletonCount
        self.spacing = spacing
        self.cardWidth = cardWidth
        self.fetch = fetch
        self.card = card
    }
}
