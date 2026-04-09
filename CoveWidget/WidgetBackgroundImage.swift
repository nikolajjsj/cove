import SwiftUI

/// A full-bleed image that fills the entire available area, intended for use
/// as a background in the small and medium widget layouts.
///
/// The image is placed as an `.overlay` on `Color.clear` so that
/// `.aspectRatio(contentMode: .fill)` covers the area visually without
/// expanding the layout frame beyond the container bounds. `.clipped()`
/// trims any overflow.
///
/// When no image data is available (or it can't be decoded) the view
/// falls back to a subtle gradient so the widget still looks presentable.
struct WidgetBackgroundImage: View {
    let imageData: Data?

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Color.clear
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
        } else {
            LinearGradient(
                colors: [.secondary.opacity(0.3), .secondary.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
