import SwiftUI

/// The Cove mark, sized for whichever onboarding stage is showing.
///
/// Shared between both panes so `matchedGeometryEffect` can carry it from the
/// centre of the welcome screen up into the header of the connect form.
struct OnboardingWordmark: View {
    var isCompact: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var fullGlyph: CGFloat = 76
    @ScaledMetric(relativeTo: .title) private var compactGlyph: CGFloat = 44

    var body: some View {
        VStack(spacing: isCompact ? 6 : 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: isCompact ? compactGlyph : fullGlyph))
                .foregroundStyle(.white, .white.opacity(0.22))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .accessibilityHidden(true)

            Text("Cove")
                .font(isCompact ? .title2 : .largeTitle)
                .bold()
                .foregroundStyle(.white)

            if !isCompact {
                Text("Your media, everywhere.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cove. Your media, everywhere.")
    }
}
