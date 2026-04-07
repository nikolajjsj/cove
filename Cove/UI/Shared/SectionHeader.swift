import SwiftUI

/// A reusable section header typically used to label horizontal rails and content sections.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var imageColor: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(imageColor)
                    .font(.title3)
            }
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

#if DEBUG
    #Preview("Text Only") {
        SectionHeader(title: "Recently Added")
            .padding()
    }

    #Preview("With Icon") {
        SectionHeader(
            title: "Favorites",
            systemImage: "heart.fill",
            imageColor: .red
        )
        .padding()
    }
#endif
