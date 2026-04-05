import SwiftUI
internal import Combine

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

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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

                // MARK: - App Icon

                ZStack {
                    // Glow behind icon
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.accentColor.opacity(0.25),
                                    Color.accentColor.opacity(0.0),
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .opacity(iconOpacity)

                    // The icon itself
                    Image(systemName: "play.rectangle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.7),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 16, y: 4)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // MARK: - App Title

                Text("Cove")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 20)
                    .opacity(titleOpacity)

                Text("for Jellyfin")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
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
        .onReceive(timer) { _ in
            dotCount += 1
        }
    }
}

#Preview {
    LaunchView()
}
