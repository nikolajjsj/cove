import SwiftUI

/// A chip for filtering by minimum community rating.
struct RatingChip: View {
    @Binding var minRating: Double?

    private var label: String {
        minRating.map { "\(Int($0))+ ★" } ?? "Rating"
    }

    var body: some View {
        Menu {
            Picker("Min Rating", selection: $minRating) {
                Text("Any Rating").tag(Double?.none)
                Text("6+ ★").tag(Double?.some(6))
                Text("7+ ★").tag(Double?.some(7))
                Text("8+ ★").tag(Double?.some(8))
                Text("9+ ★").tag(Double?.some(9))
            }
        } label: {
            Label(label, systemImage: minRating != nil ? "star.fill" : "star")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(minRating != nil ? .yellow : .secondary)
        .buttonBorderShape(.capsule)
    }
}
