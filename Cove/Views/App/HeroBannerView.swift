internal import Combine
import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

let CORNER_RADIUS = CGFloat(16)

// MARK: - Hero Banner Carousel

struct HeroBannerView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var items: [MediaItem] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var lastInteractionDate = Date()
    @State private var lastAdvanceDate = Date()

    /// Auto-advance ticker — fires every second so we can check elapsed time.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Seconds between auto-advances.
    private let advanceInterval: TimeInterval = 8
    /// Seconds to wait after user interaction before resuming auto-advance.
    private let resumeDelay: TimeInterval = 12

    /// Banner height — compact enough to leave room for Continue Watching below.
    private let bannerHeight: CGFloat = 240

    var body: some View {
        Group {
            if isLoading {
                bannerSkeleton
            } else if !items.isEmpty {
                bannerCarousel
            }
        }
        .task {
            await loadSuggestions()
        }
    }

    // MARK: - Carousel

    private var bannerCarousel: some View {
        TabView(selection: $currentIndex) {
            ForEach(items.enumerated(), id: \.element.id) { index, item in
                BannerPageView(item: item)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .aspectRatio(16 / 9, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: CORNER_RADIUS))
        .onChange(of: currentIndex) { _, _ in
            lastInteractionDate = Date()
            lastAdvanceDate = Date()
        }
        .onReceive(ticker) { now in
            guard items.count > 1 else { return }
            let sinceInteraction = now.timeIntervalSince(lastInteractionDate)
            let sinceAdvance = now.timeIntervalSince(lastAdvanceDate)

            // Don't auto-advance if the user recently interacted.
            guard sinceInteraction >= resumeDelay else { return }
            // Only advance once per interval.
            guard sinceAdvance >= advanceInterval else { return }

            withAnimation(.easeInOut(duration: 0.6)) {
                currentIndex = (currentIndex + 1) % items.count
            }
            lastAdvanceDate = now
        }
    }

    // MARK: - Skeleton

    private var bannerSkeleton: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.secondarySystemBackground))
            .frame(height: bannerHeight)
            .overlay {
                ProgressView()
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
                            .font(.system(.title2, design: .default, weight: .bold))
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
        let backdropURL = authManager.provider.imageURL(
            for: item, type: .backdrop, maxSize: CGSize(width: 1280, height: 720)
        )
        let primaryURL = authManager.provider.imageURL(
            for: item, type: .primary, maxSize: CGSize(width: 600, height: 900)
        )

        return MediaImage(
            url: backdropURL ?? primaryURL,
            aspectRatio: nil,
            placeholderIcon: "film",
            cornerRadius: CORNER_RADIUS,
            showsLoadingIndicator: false
        )
    }
}
