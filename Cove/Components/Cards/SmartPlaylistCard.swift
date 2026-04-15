import SwiftUI

/// A visually rich landscape card for a smart playlist preset.
///
/// Each card has a gradient background with a large ghosted icon
/// and clean typography, matching the visual language of `GenreCard`.
struct SmartPlaylistCard: View {
    let preset: SmartPlaylist

    static let cardWidth: CGFloat = 172
    static let cardHeight: CGFloat = 100
    static let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            // MARK: Background gradient
            LinearGradient(
                colors: preset.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // MARK: Decorative background icon (ghosted, rotated)
            Image(systemName: preset.icon)
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .offset(x: 36, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .clipped()

            // MARK: Subtle inner top highlight (glass sheen)
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            // MARK: Bottom scrim for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // MARK: Label group — bottom leading
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: preset.icon)
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.85))

                    Text(preset.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(.primary.opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - Button Style

/// A spring-based button style for smart playlist cards, matching the genre card interaction.
struct SmartPlaylistCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Smart Playlist Cards") {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(SmartPlaylist.presets) { preset in
                    SmartPlaylistCard(preset: preset)
                }
            }
            .padding()
        }
        .background(.background)
    }
#endif
