import SwiftUI

/// Renders a pre-fetched thumbnail image from raw `Data`, or falls back
/// to a ``WidgetImagePlaceholder`` when no image data is available.
///
/// The image is placed inside a fixed-aspect-ratio container using an
/// overlay so that `.fill` covers the area without overflowing the
/// layout frame. The `clipShape` then clips the drawn content to the
/// container bounds.
///
/// This view exists because `AsyncImage` does not work in WidgetKit —
/// widgets are rendered as static snapshots with no live view lifecycle.
/// Images must be downloaded in the timeline provider and passed as `Data`.
struct WidgetThumbnailView: View {
    let imageData: Data?
    var cornerRadius: Double = 6
    var aspectRatio: Double = 16.0 / 9.0

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
        } else {
            WidgetImagePlaceholder()
        }
    }
}
