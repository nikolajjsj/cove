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
///     try await catalog.repository.resumeItems(scope: catalog.scope)
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
    /// Re-runs `fetch` in place when it changes — Home passes the catalogue
    /// generation so rows that land during a sync appear without a rebuild.
    let reloadKey: AnyHashable
    /// Space below the rail while it is visible. Home stacks sections with zero
    /// spacing and lets each visible one bring its own, so a hidden rail takes
    /// no room while it stays mounted and keeps listening for rows.
    let sectionSpacing: CGFloat

    // MARK: - State

    @State private var loader = CollectionLoader<MediaItem>()

    /// Controls the animated show/hide transition. Starts `true` and animates
    /// to `false` when the fetch returns empty or fails.
    @State private var isVisible = true

    // MARK: - Body

    var body: some View {
        Group {
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
                .padding(.bottom, sectionSpacing)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: phaseKey)
            } else {
                // Hidden, not gone: the task below must survive so a later
                // reload can bring the rail back.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: reloadKey) {
            await loader.load(fetch)
        }
        .onChange(of: phaseKey) { _, phase in
            if phase == "loaded", !isVisible {
                withAnimation(.easeInOut(duration: 0.25)) { isVisible = true }
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
    ///     try await catalog.repository.nextUp(scope: catalog.scope)
    /// } card: { item in
    ///     UpNextCard(item: item)
    /// }
    /// ```
    init(
        title: String,
        skeletonCount: Int = 4,
        spacing: CGFloat = 12,
        cardWidth: ((MediaItem) -> CGFloat)? = nil,
        reloadKey: AnyHashable = 0,
        sectionSpacing: CGFloat = 0,
        @ViewBuilder skeleton: @escaping () -> Skeleton,
        fetch: @escaping @Sendable () async throws -> [MediaItem],
        @ViewBuilder card: @escaping (MediaItem) -> Card
    ) {
        self.header = SectionHeader(title: title)
        self.skeleton = skeleton()
        self.skeletonCount = skeletonCount
        self.spacing = spacing
        self.cardWidth = cardWidth
        self.reloadKey = reloadKey
        self.sectionSpacing = sectionSpacing
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
    ///     fetch: { try await catalog.repository.latest(libraryId: library.id.rawValue, ...) },
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
        reloadKey: AnyHashable = 0,
        sectionSpacing: CGFloat = 0,
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
        self.reloadKey = reloadKey
        self.sectionSpacing = sectionSpacing
        self.fetch = fetch
        self.card = card
    }
}
