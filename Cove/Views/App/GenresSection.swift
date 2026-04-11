import DataLoading
import JellyfinProvider
import Models
import SwiftUI

// MARK: - Section

/// A "Browse by Genre" home screen section showing visually rich genre cards
/// in a horizontal scroll rail. Only shown when a video library (movies or TV)
/// is available on the server.
struct GenresSection: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var loader = CollectionLoader<MediaItem>()
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            Group {
                switch loader.phase {
                case .loading:
                    GenresSectionShell(isLoaded: false) {
                        GenresSectionSkeleton()
                    }

                case .loaded(let items):
                    GenresSectionShell(isLoaded: true) {
                        GenreCardRail(genres: items, libraryId: videoLibrary?.id)
                    }

                case .empty, .failed:
                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
                        }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: phaseKey)
            .task { await loadGenres() }
        }
    }

    private var videoLibrary: MediaLibrary? {
        appState.libraries.first {
            $0.collectionType == .movies || $0.collectionType == .tvshows
        }
    }

    private func loadGenres() async {
        guard let library = videoLibrary else {
            withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
            return
        }
        let provider = authManager.provider
        await loader.load { try await provider.genres(in: library) }
    }

    private var phaseKey: String {
        switch loader.phase {
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        }
    }
}

// MARK: - Button Style

private struct GenreCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shell (header + content slot)

/// Wraps the section header above any content slot.
private struct GenresSectionShell<Content: View>: View {
    let isLoaded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GenresSectionHeader()
                .padding(.horizontal)
            content
        }
    }
}

// MARK: - Header

private struct GenresSectionHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Genres")
                .font(.title2)
                .bold()
        }
    }
}

// MARK: - Card Rail

private struct GenreCardRail: View {
    let genres: [MediaItem]
    let libraryId: ItemID?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(genres) { genre in
                    NavigationLink(value: VideoGenreRoute(genre: genre.title, libraryId: libraryId))
                    {
                        GenreCard(name: genre.title)
                    }
                    .buttonStyle(GenreCardButtonStyle())
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - Skeleton

private struct GenresSectionSkeleton: View {
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(0..<7, id: \.self) { index in
                    GenreCardSkeleton()
                        .opacity(skeletonOpacity(at: index))
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
    }

    private func skeletonOpacity(at index: Int) -> Double {
        let fade = 1.0 - (Double(index) * 0.12)
        return max(fade, 0.3)
    }
}

private struct GenreCardSkeleton: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: GenreCard.cornerRadius)
            .fill(
                LinearGradient(
                    colors: shimmer
                        ? [
                            Color.primary.opacity(0.08), Color.primary.opacity(0.05),
                            Color.primary.opacity(0.08),
                        ]
                        : [
                            Color.primary.opacity(0.05), Color.primary.opacity(0.08),
                            Color.primary.opacity(0.05),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: GenreCard.cardWidth, height: GenreCard.cardHeight)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

// MARK: - Genre Card

/// A visually rich landscape card for a single genre.
///
/// Each card has a deterministic gradient background derived from the genre name
/// so colours stay consistent across launches, alongside a large ghosted icon
/// and clean typography.
struct GenreCard: View {
    let name: String

    static let cardWidth: CGFloat = 172
    static let cardHeight: CGFloat = 100
    static let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            // MARK: Background gradient
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // MARK: Decorative background icon (ghosted, rotated)
            Image(systemName: GenreIconMap.icon(for: name))
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .offset(x: 36, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .clipped()

            // MARK: Subtle inner top highlight (glass sheen)
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            // MARK: Bottom scrim for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // MARK: Label group — bottom leading
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: GenreIconMap.icon(for: name))
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.85))

                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(.primary.opacity(0.4), lineWidth: 1)
        }
    }

    // MARK: Gradient

    private var gradientColors: [Color] {
        let index = abs(name.deterministicHash) % GenreGradients.palette.count
        return GenreGradients.palette[index]
    }
}

// MARK: - Gradient Palette

/// Hand-tuned gradient pairs for genre cards.
/// Each pair is visually distinct and renders well at small sizes.
private enum GenreGradients {
    static let palette: [[Color]] = [
        // Electric blue → deep indigo
        [
            Color(red: 0.18, green: 0.40, blue: 0.95),
            Color(red: 0.38, green: 0.18, blue: 0.82),
        ],
        // Crimson → warm orange
        [
            Color(red: 0.88, green: 0.18, blue: 0.28),
            Color(red: 0.96, green: 0.56, blue: 0.14),
        ],
        // Forest green → ocean teal
        [
            Color(red: 0.08, green: 0.62, blue: 0.38),
            Color(red: 0.06, green: 0.44, blue: 0.72),
        ],
        // Deep purple → hot pink
        [
            Color(red: 0.52, green: 0.12, blue: 0.82),
            Color(red: 0.94, green: 0.22, blue: 0.62),
        ],
        // Teal → cyan
        [
            Color(red: 0.06, green: 0.60, blue: 0.72),
            Color(red: 0.06, green: 0.84, blue: 0.80),
        ],
        // Tangerine → rose
        [
            Color(red: 0.98, green: 0.48, blue: 0.08),
            Color(red: 0.88, green: 0.18, blue: 0.48),
        ],
        // Midnight blue → slate
        [
            Color(red: 0.10, green: 0.14, blue: 0.46),
            Color(red: 0.26, green: 0.32, blue: 0.62),
        ],
        // Olive → amber
        [
            Color(red: 0.48, green: 0.42, blue: 0.08),
            Color(red: 0.82, green: 0.60, blue: 0.12),
        ],
        // Magenta → deep purple
        [
            Color(red: 0.82, green: 0.08, blue: 0.52),
            Color(red: 0.40, green: 0.06, blue: 0.68),
        ],
        // Slate teal → deep green
        [
            Color(red: 0.12, green: 0.48, blue: 0.52),
            Color(red: 0.06, green: 0.32, blue: 0.28),
        ],
    ]
}

// MARK: - Genre Icon Map

/// Maps common genre name substrings to SF Symbols using fuzzy matching.
enum GenreIconMap {
    static func icon(for genre: String) -> String {
        let lower = genre.lowercased()
        for (keyword, symbol) in orderedMapping {
            if lower.localizedStandardContains(keyword) { return symbol }
        }
        return "film"
    }

    /// Ordered so more-specific matches (e.g. "sci-fi") come before general ones.
    private static let orderedMapping: [(String, String)] = [
        ("science fiction", "atom"),
        ("sci-fi", "atom"),
        ("action", "flame.fill"),
        ("adventure", "map.fill"),
        ("animation", "sparkles"),
        ("anime", "sparkles"),
        ("comedy", "face.smiling.fill"),
        ("crime", "magnifyingglass"),
        ("documentary", "doc.text.fill"),
        ("drama", "theatermasks.fill"),
        ("family", "figure.2.and.child.holdinghands"),
        ("fantasy", "wand.and.stars"),
        ("history", "building.columns.fill"),
        ("horror", "moon.stars.fill"),
        ("kids", "figure.and.child.holdinghands"),
        ("music", "music.note"),
        ("mystery", "questionmark.circle.fill"),
        ("romance", "heart.fill"),
        ("sport", "trophy.fill"),
        ("thriller", "bolt.fill"),
        ("war", "shield.fill"),
        ("western", "sun.dust.fill"),
        ("reality", "eye.fill"),
        ("talk", "mic.fill"),
        ("news", "newspaper.fill"),
    ]
}

// MARK: - Stable Hash Extension

extension String {
    /// DJB2 hash — stable across process launches, unlike Swift's `hashValue`.
    fileprivate var deterministicHash: Int {
        var hash = 5381
        for byte in utf8 {
            hash = ((hash &<< 5) &+ hash) &+ Int(byte)
        }
        return hash
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Cards") {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(
                    [
                        "Action", "Comedy", "Drama", "Horror",
                        "Science Fiction", "Romance", "Thriller",
                        "Animation", "Documentary", "Fantasy",
                    ],
                    id: \.self
                ) { genre in
                    GenreCard(name: genre)
                }
            }
            .padding()
        }
        .background(.background)
    }

    #Preview("Section – Loading") {
        GenresSectionShell(isLoaded: false) {
            GenresSectionSkeleton()
        }
        .padding()
        .background(.background)
    }
#endif
