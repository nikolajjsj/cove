import SwiftUI

/// A polished launch screen shown while the app restores the user's session.
///
/// Features a centered app icon that fades and scales in with a gentle pulse,
/// the app name below it, and a subtle loading indicator at the bottom.
struct LaunchView: View {
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0.0
    @State private var titleOpacity: Double = 0.0
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var dotCount: Int = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - App Title

                Text("Cove")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .padding(.top, 20)
                    .opacity(titleOpacity)

                Text("for Jellyfin")
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .opacity(titleOpacity)

                Spacer()

                // MARK: - Loading Indicator

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .scaleEffect(dotCount % 3 == index ? 1.4 : 0.7)
                            .opacity(dotCount % 3 == index ? 1.0 : 0.35)
                            .animation(
                                .easeInOut(duration: 0.4),
                                value: dotCount
                            )
                    }
                }
                .padding(.bottom, 60)
                .opacity(titleOpacity)
            }
        }
        .onAppear {
            // Icon entrance
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }

            // Title fades in slightly after icon
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                titleOpacity = 1.0
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                dotCount += 1
            }
        }
    }
}

#Preview {
    LaunchView()
}
