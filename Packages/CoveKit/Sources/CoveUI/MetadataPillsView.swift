import SwiftUI

// MARK: - MetadataPillsView

/// A horizontally-scrolling row of ``MetadataPill`` capsules.
///
/// Each pill is rendered as a compact capsule with an optional SF Symbol icon,
/// a text label, and an optional tint color.
///
/// ```swift
/// MetadataPillsView([
///     .communityRating(8.5),
///     .criticRating(92),
///     .genre("Drama"),
/// ].compactMap { $0 })
/// ```
///
/// If the pills array is empty the view renders nothing.
public struct MetadataPillsView: View {

    private let pills: [MetadataPill]

    /// Creates a horizontally-scrolling metadata pill row.
    ///
    /// - Parameter pills: The pills to display. Pass an empty array to render nothing.
    public init(_ pills: [MetadataPill]) {
        self.pills = pills
    }

    public var body: some View {
        if !pills.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(pills, id: \.label) { pill in
                        pillView(pill)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func pillView(_ pill: MetadataPill) -> some View {
        HStack(spacing: 4) {
            if let icon = pill.icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(pill.label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(pill.tint ?? .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.secondary.opacity(0.15))
        )
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Metadata Pills") {
        VStack(spacing: 20) {
            MetadataPillsView([
                MetadataPill(icon: "star.fill", label: "8.5", tint: .yellow),
                MetadataPill(icon: "heart.fill", label: "92%", tint: .green),
                MetadataPill(label: "Drama"),
                MetadataPill(icon: "checkmark.circle.fill", label: "Played", tint: .green),
            ])

            MetadataPillsView([
                MetadataPill(icon: "rectangle.stack.fill", label: "12 items")
            ])

            // Empty — should render nothing
            MetadataPillsView([])
        }
        .padding()
    }
#endif
