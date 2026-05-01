import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

private let heroBannerCornerRadius: CGFloat = 16

// MARK: - Hero Banner Carousel

struct HeroBannerView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var lastInteractionDate = Date()
    @State private var lastAdvanceDate = Date()

    /// Seconds between auto-advances.
    private let advanceInterval: TimeInterval = 8
    /// Seconds to wait after user interaction before resuming auto-advance.
    private let resumeDelay: TimeInterval = 12

    /// Banner height — compact enough to leave room for Continue Watching below.
    private let bannerHeight: CGFloat = 240

    var body: some View {
        Group {
            if isLoading {
                BannerSkeletonView(height: bannerHeight, cornerRadius: heroBannerCornerRadius)
            } else if !items.isEmpty {
                BannerCarouselView(
                    items: items,
                    currentIndex: $currentIndex,
                    lastInteractionDate: $lastInteractionDate,
                    lastAdvanceDate: $lastAdvanceDate,
                    advanceInterval: advanceInterval,
                    resumeDelay: resumeDelay,
                    cornerRadius: heroBannerCornerRadius
                )
            }
        }
        .task {
            await loadSuggestions()
        }
    }

    // MARK: - Data Loading

    private func loadSuggestions() async {
        // Already have data — nothing to do. The API-level cache (10 min)
        // ensures the next cold load is fast too.
        guard items.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let suggested = try await authManager.provider.suggestedItems(limit: 8)
            // Prefer items with backdrop images; take up to 5.
            let withBackdrops = suggested.filter { $0.imageTags?[.backdrop] != nil }
            var result = Array(withBackdrops.prefix(5))
            // If not enough backdrop items, fill from the rest.
            if result.count < 3 {
                let remaining =
                    suggested
                    .filter { !result.contains($0) }
                    .prefix(5 - result.count)
                result.append(contentsOf: remaining)
            }
            items = result
        } catch {
            items = []
        }
    }
}

// MARK: - Banner Carousel

private struct BannerCarouselView: View {
    let items: [MediaItem]
    @Binding var currentIndex: Int
    @Binding var lastInteractionDate: Date
    @Binding var lastAdvanceDate: Date
    let advanceInterval: TimeInterval
    let resumeDelay: TimeInterval
    let cornerRadius: CGFloat

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(items.enumerated(), id: \.element.id) { index, item in
                BannerPageView(item: item)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .aspectRatio(16 / 9, contentMode: .fill)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .onChange(of: currentIndex) { _, _ in
            lastInteractionDate = Date()
            lastAdvanceDate = Date()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard items.count > 1 else { continue }
                let now = Date()
                let sinceInteraction = now.timeIntervalSince(lastInteractionDate)
                let sinceAdvance = now.timeIntervalSince(lastAdvanceDate)
                guard sinceInteraction >= resumeDelay else { continue }
                guard sinceAdvance >= advanceInterval else { continue }
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
                lastAdvanceDate = now
            }
        }
    }
}

// MARK: - Banner Skeleton

private struct BannerSkeletonView: View {
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(height: height)
            .overlay {
                ProgressView()
            }
    }
}

// MARK: - Single Banner Page

private struct BannerPageView: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationLink(value: item) {
            // Color.clear drives the layout size; image + text go in overlays
            // so .fill never pushes the frame larger than the TabView page.
            Color.clear
                .overlay { backdropImage }
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: .black.opacity(0.45), location: 0.55),
                            .init(color: .black.opacity(0.85), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                        HStack(spacing: 8) {
                            if let year = item.productionYear {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            if let rating = item.communityRating, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                    Text(rating, format: .number.precision(.fractionLength(1)))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }

                            if let officialRating = item.officialRating, !officialRating.isEmpty {
                                Text(officialRating)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(.white.opacity(0.2))
                                    )
                            }
                        }

                        if let tagline = item.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                                .italic()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 38)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Backdrop Image

    private var backdropImage: some View {
        BannerBackdropImage(item: item, cornerRadius: heroBannerCornerRadius)
    }
}

// MARK: - Backdrop Image

private struct BannerBackdropImage: View {
    let item: MediaItem
    let cornerRadius: CGFloat
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        let backdropURL = authManager.provider.imageURL(
            for: item, type: .backdrop, maxSize: CGSize(width: 1280, height: 720)
        )
        let primaryURL = authManager.provider.imageURL(
            for: item, type: .primary, maxSize: CGSize(width: 600, height: 900)
        )
        MediaImage(
            url: backdropURL ?? primaryURL,
            aspectRatio: nil,
            placeholderIcon: "film",
            cornerRadius: cornerRadius,
            showsLoadingIndicator: false
        )
    }
}
