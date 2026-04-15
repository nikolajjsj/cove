import SwiftUI

/// A text section that shows a truncated overview with an expand/collapse button.
///
/// The "Show More" button only appears when the text is actually truncated
/// by the line limit. When the full text fits within the limit, no button
/// is shown.
///
/// Used by MovieDetailView, SeriesDetailView, and CollectionDetailView to
/// display item overviews with consistent behavior.
struct ExpandableOverview: View {
    let text: String
    var lineLimit: Int = 4
    var font: Font = .body

    @State private var isExpanded = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Whether the text is actually being truncated by the line limit.
    ///
    /// Compares the measured height of the line-limited text against the
    /// full (unlimited) text. A small epsilon accounts for floating-point
    /// rounding differences.
    private var isTruncated: Bool {
        fullHeight > limitedHeight + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : lineLimit)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    if !isExpanded {
                        limitedHeight = height
                    }
                }
                .background {
                    // Hidden full text to measure the unrestricted height
                    Text(text)
                        .font(font)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            fullHeight = height
                        }
                }

            if isTruncated || isExpanded {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}
