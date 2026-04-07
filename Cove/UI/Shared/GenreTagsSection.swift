import CoveUI
import SwiftUI

/// A section displaying genre names as styled chips in a flow layout.
///
/// Replaces the duplicated `genresTags(_:)` private functions in
/// MovieDetailView and SeriesDetailView.
struct GenreTagsSection: View {
    let genres: [String]

    var body: some View {
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Genres")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
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
