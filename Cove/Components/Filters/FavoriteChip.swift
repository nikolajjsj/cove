import SwiftUI

/// A toggle chip for filtering to favorited items only.
struct FavoriteChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label("Favorites", systemImage: isOn ? "heart.fill" : "heart")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .pink : .secondary)
        .buttonBorderShape(.capsule)
    }
}
