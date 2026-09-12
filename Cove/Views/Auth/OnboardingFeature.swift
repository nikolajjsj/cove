import SwiftUI

/// One promise made on the welcome pane.
struct OnboardingFeature: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String

    static let all: [OnboardingFeature] = [
        OnboardingFeature(
            systemImage: "play.rectangle.on.rectangle",
            title: "Your whole library",
            detail: "Films, shows, and music from your own Jellyfin server."
        ),
        OnboardingFeature(
            systemImage: "arrow.down.circle",
            title: "Take it offline",
            detail: "Download anything and keep watching without a connection."
        ),
        OnboardingFeature(
            systemImage: "lock.shield",
            title: "Nobody else's business",
            detail: "Your server, your data. Cove never phones anyone home."
        ),
    ]
}

/// A single feature line, icon leading.
struct OnboardingFeatureRow: View {
    let feature: OnboardingFeature

    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: iconWidth, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
