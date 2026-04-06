import Models
import SwiftUI

/// A reusable horizontal scroll rail of media items with skeleton loading.
///
/// Used for "More Like This", "Special Features", "Trailers", etc.
/// Loads data lazily when the section scrolls into view.
struct MediaItemRail: View {
    let title: String
    let loader: @Sendable () async throws -> [MediaItem]

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        if isLoading {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonItemCard(
                                    width: defaultCardWidth,
                                    aspectRatio: defaultAspectRatio
                                )
                            }
                            .transition(.opacity)
                        } else {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    LibraryItemCard(item: item)
                                        .frame(width: cardWidth(for: item))
                                }
                                .buttonStyle(.plain)
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isLoading)
            .task {
                await loadItems()
            }
        }
    }

    private func loadItems() async {
        isLoading = true
        do {
            let result = try await loader()
            guard !Task.isCancelled else { return }
            if result.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isVisible = false
                }
            } else {
                items = result
                isLoading = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isVisible = false
            }
        }
    }

    private var defaultCardWidth: CGFloat { 130 }
    private var defaultAspectRatio: CGFloat { 2.0 / 3.0 }

    private func cardWidth(for item: MediaItem) -> CGFloat {
        switch item.mediaType {
        case .album, .artist, .track, .playlist: 140
        default: 130
        }
    }
}

// MARK: - Skeleton Card (for rail loading state)

/// A placeholder card matching `LibraryItemCard` dimensions.
private struct SkeletonItemCard: View {
    let width: CGFloat
    let aspectRatio: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .aspectRatio(aspectRatio, contentMode: .fit)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: width * 0.6, height: 10)
        }
        .frame(width: width)
    }
}
