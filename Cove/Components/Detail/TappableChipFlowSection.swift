import CoveUI
import Models
import SwiftUI

/// A variant of `ChipFlowSection` where each chip is a tappable `NavigationLink`
/// that pushes a `VideoGenreRoute` onto the navigation stack.
///
/// Used in video detail views so that tapping a genre chip navigates to a
/// filtered grid of movies or series in that genre.
///
/// ```swift
/// TappableChipFlowSection(
///     title: "Genres",
///     items: movie.genres,
///     libraryId: library?.id
/// )
/// ```
struct TappableChipFlowSection: View {
    let title: String
    let items: [String]
    let libraryId: ItemID?

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        NavigationLink(value: VideoGenreRoute(genre: item, libraryId: libraryId)) {
                            GenreChip(name: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Genre Chip

private struct GenreChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
            )
            .contentShape(.rect(cornerRadius: 8))
            .hoverEffect(.highlight)
    }
}
