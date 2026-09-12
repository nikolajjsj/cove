import SwiftUI

/// The drifting aurora behind onboarding.
///
/// A 3×3 `MeshGradient` whose interior control points drift on slow, offset sine
/// curves. The corners stay pinned so the field never tears at the edges, and the
/// palette is fixed rather than scheme-dependent — it is the one place in the app
/// that sets its own stage, and white type has to stay legible on it in both
/// light and dark.
struct OnboardingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Deep water, shading to the accent. Read top-left to bottom-right.
    private static let palette: [Color] = [
        Color(red: 0.04, green: 0.08, blue: 0.18),
        Color(red: 0.05, green: 0.16, blue: 0.35),
        Color(red: 0.03, green: 0.09, blue: 0.22),
        Color(red: 0.06, green: 0.24, blue: 0.45),
        Color(red: 0.10, green: 0.42, blue: 0.62),
        Color(red: 0.05, green: 0.18, blue: 0.38),
        Color(red: 0.03, green: 0.07, blue: 0.16),
        Color(red: 0.05, green: 0.20, blue: 0.40),
        Color(red: 0.02, green: 0.05, blue: 0.12),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(
            // Sink the lower half so form fields and buttons keep their contrast
            // wherever the bright band happens to drift.
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        MeshGradient(width: 3, height: 3, points: points(at: time), colors: Self.palette)
    }

    /// Corners pinned, edges and centre drifting on offset periods so the motion
    /// never visibly loops.
    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ base: Float, _ amount: Float, _ period: Double, _ phase: Double) -> Float {
            base + amount * Float(sin(time / period + phase))
        }

        return [
            SIMD2(0, 0),
            SIMD2(drift(0.5, 0.12, 4.1, 0), 0),
            SIMD2(1, 0),
            SIMD2(0, drift(0.5, 0.10, 5.3, 1.2)),
            SIMD2(drift(0.5, 0.18, 3.7, 2.1), drift(0.5, 0.14, 4.9, 0.6)),
            SIMD2(1, drift(0.5, 0.10, 6.1, 2.8)),
            SIMD2(0, 1),
            SIMD2(drift(0.5, 0.12, 4.7, 3.4), 1),
            SIMD2(1, 1),
        ]
    }
}
