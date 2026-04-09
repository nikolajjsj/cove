import SwiftUI

/// A placeholder thumbnail shown when a media item has no image available.
/// Used across all widget size variants for consistent styling.
struct WidgetImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
