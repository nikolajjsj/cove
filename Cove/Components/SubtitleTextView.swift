import SwiftUI

/// A reusable view that renders subtitle text with configurable appearance settings.
///
/// Used both in the video player overlay and in the subtitle settings preview.
struct SubtitleTextView: View {
    let text: String
    let size: SubtitleSize
    let color: SubtitleColor
    let background: SubtitleBackground

    var body: some View {
        switch background {
        case .none:
            PlainSubtitleText(text: text, font: size.font, color: color.color)
                .padding(.horizontal)

        case .outline:
            OutlinedSubtitleText(text: text, font: size.font, color: color.color)
                .padding(.horizontal)

        case .dropShadow:
            ShadowedSubtitleText(text: text, font: size.font, color: color.color)
                .padding(.horizontal)

        case .semiTransparent:
            BackedSubtitleText(text: text, font: size.font, color: color.color, opacity: 0.6)
                .padding(.horizontal)

        case .opaque:
            BackedSubtitleText(text: text, font: size.font, color: color.color, opacity: 1.0)
                .padding(.horizontal)
        }
    }
}

// MARK: - Style Variants

/// Plain subtitle text with no outline, shadow, or background.
private struct PlainSubtitleText: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }
}

/// Subtitle text with an 8-direction black stroke outline.
private struct OutlinedSubtitleText: View {
    let text: String
    let font: Font
    let color: Color

    private let outlineWidth: CGFloat = 1.2

    private var offsets: [CGSize] {
        [
            CGSize(width: -outlineWidth, height: -outlineWidth),
            CGSize(width: 0, height: -outlineWidth),
            CGSize(width: outlineWidth, height: -outlineWidth),
            CGSize(width: -outlineWidth, height: 0),
            CGSize(width: outlineWidth, height: 0),
            CGSize(width: -outlineWidth, height: outlineWidth),
            CGSize(width: 0, height: outlineWidth),
            CGSize(width: outlineWidth, height: outlineWidth),
        ]
    }

    var body: some View {
        ZStack {
            // Black stroke: render the same text offset in 8 directions
            ForEach(offsets, id: \.debugDescription) { offset in
                Text(text)
                    .font(font)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .offset(x: offset.width, y: offset.height)
            }
            // Colored fill on top
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
        }
    }
}

/// Subtitle text with a drop shadow behind it.
private struct ShadowedSubtitleText: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.8), radius: 4, x: 1, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 2, y: 2)
    }
}

/// Subtitle text on a rounded-rect background with configurable opacity.
private struct BackedSubtitleText: View {
    let text: String
    let font: Font
    let color: Color
    let opacity: Double

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.black.opacity(opacity))
            .clipShape(.rect(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview("Outline") {
    ZStack {
        Color.gray
        SubtitleTextView(
            text: "Hello, this is a subtitle.",
            size: .medium,
            color: .white,
            background: .outline
        )
    }
}

#Preview("Drop Shadow") {
    ZStack {
        Color.gray
        SubtitleTextView(
            text: "Hello, this is a subtitle.",
            size: .large,
            color: .yellow,
            background: .dropShadow
        )
    }
}

#Preview("Semi-Transparent") {
    ZStack {
        Color.gray
        SubtitleTextView(
            text: "Hello, this is a subtitle.",
            size: .medium,
            color: .white,
            background: .semiTransparent
        )
    }
}
