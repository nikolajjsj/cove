import SwiftUI

/// A text section that shows a truncated overview with an expand/collapse button.
///
/// Used by MovieDetailView, SeriesDetailView, and CollectionDetailView to
/// display item overviews with consistent behavior.
struct ExpandableOverview: View {
    let text: String
    var lineLimit: Int = 4
    var font: Font = .body
    /// When set, the expand button only appears if the text exceeds this character count.
    var expandThreshold: Int? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : lineLimit)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)

            if showExpandButton {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var showExpandButton: Bool {
        if let threshold = expandThreshold {
            return text.count > threshold
        }
        return true
    }
}
