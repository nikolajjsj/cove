import SwiftUI

/// A horizontal row of text items separated by centered dot characters.
///
/// Used for subtitle lines in hero sections (e.g. "2024 · PG-13 · 2h 15m").
///
/// ```swift
/// DotSeparatedText(parts: ["2024", "PG-13", "2h 15m"])
/// ```
struct DotSeparatedText: View {
    let parts: [String]
    var font: Font = .subheadline
    var foregroundStyle: HierarchicalShapeStyle = .secondary

    var body: some View {
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(foregroundStyle)
                            .font(font)
                    }
                    Text(part)
                        .font(font)
                        .foregroundStyle(foregroundStyle)
                }
            }
        }
    }
}
