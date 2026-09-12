import SwiftUI

/// The first thing anyone sees: what Cove is, and one way forward.
struct WelcomePane: View {
    let namespace: Namespace.ID
    let onContinue: () -> Void

    /// Drives the staggered entrance. Set once on appear.
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            OnboardingWordmark(isCompact: false)
                .matchedGeometryEffect(id: "wordmark", in: namespace)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(OnboardingFeature.all.enumerated()), id: \.element.id) {
                    index, feature in
                    OnboardingFeatureRow(feature: feature)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 14)
                        .animation(
                            entrance.delay(reduceMotion ? 0 : 0.18 + Double(index) * 0.08),
                            value: hasAppeared
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 36)

            Spacer(minLength: 0)

            Button(action: onContinue) {
                Text("Connect to Server")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .opacity(hasAppeared ? 1 : 0)
                .animation(entrance.delay(reduceMotion ? 0 : 0.5), value: hasAppeared)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .animation(entrance, value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    private var entrance: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.55)
    }
}
