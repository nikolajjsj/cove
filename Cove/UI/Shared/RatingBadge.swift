import SwiftUI

/// A compact star-rating badge showing "★ 7.4" style ratings.
///
/// Renders nothing when the rating is `nil` or non-positive, so it can be
/// placed unconditionally in any layout without extra `if let` guards.
///
/// ```swift
/// // Inline in an HStack — only renders when rating exists
/// HStack {
///     Text(title)
///     Spacer()
///     RatingBadge(rating: item.communityRating)
/// }
/// ```
struct RatingBadge: View {
    let rating: Double?

    var body: some View {
        if let rating, rating > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(String(format: "%.1f", rating))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Ratings") {
        VStack(spacing: 16) {
            RatingBadge(rating: 8.7)
            RatingBadge(rating: 5.0)
            RatingBadge(rating: nil)  // renders nothing
            RatingBadge(rating: 0)  // renders nothing
        }
        .padding()
    }
#endif
