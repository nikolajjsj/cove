import SwiftUI

/// Displays an item's tagline in italic style, typically shown above the overview.
struct TaglineView: View {
    let tagline: String

    var body: some View {
        Text(tagline)
            .font(.subheadline)
            .italic()
            .foregroundStyle(.secondary)
    }
}
