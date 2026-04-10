import CoveUI
import SwiftUI

/// A reusable section that displays a list of strings as styled chips in a flow layout.
///
/// Used for genres, studios, tags, and any other list of short text labels
/// that should be presented as tappable-looking capsules.
///
/// ```swift
/// ChipFlowSection(title: "Genres", items: movie.genres)
/// ChipFlowSection(title: "Studios", items: movie.studios)
/// ```
struct ChipFlowSection: View {
    let title: String
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                }
            }
        }
    }
}
