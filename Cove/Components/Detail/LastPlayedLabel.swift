import SwiftUI

/// A subtle label showing when the user last watched/listened to this item.
/// Used on detail pages (movies, episodes) directly below the action buttons.
struct LastPlayedLabel: View {
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Text("Last watched \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }
}
