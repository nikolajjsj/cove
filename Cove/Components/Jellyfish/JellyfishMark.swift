import SwiftUI

/// The app icon's jellyfish, alive.
///
/// Draws `JellyfishGeometry` — the very curves the icon is generated from — and
/// animates the two things a jellyfish actually does: a travelling wave down
/// the arms, and the slow contraction of the bell it swims with. Because both
/// come from the same file as the icon, the creature on the first screen is
/// recognisably the one on the home screen.
///
/// Static under Reduce Motion.
struct JellyfishMark: View {
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                canvas(phase: 0, pulse: 0.5, drift: 0)
            } else {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    canvas(
                        phase: CGFloat(time) * 1.15,
                        pulse: 0.5 + 0.5 * CGFloat(sin(time * 0.85)),
                        drift: CGFloat(sin(time * 0.42)) * 0.016
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func canvas(phase: CGFloat, pulse: CGFloat, drift: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / JellyfishGeometry.reference
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(
                    CGAffineTransform(translationX: 0, y: drift * canvasSize.height)
                )
            let jelly = JellyfishGeometry()
            func shaped(_ path: CGPath) -> Path { Path(path).applying(transform) }

            // Bioluminescence pooled under the bell.
            let glowRadius = canvasSize.width * 0.42
            let glowCentre = CGPoint(
                x: jelly.hem.x * scale,
                y: jelly.hem.y * scale + drift * canvasSize.height
            )
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: glowCentre.x - glowRadius, y: glowCentre.y - glowRadius,
                        width: glowRadius * 2, height: glowRadius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [Self.glow.opacity(0.34), Self.glow.opacity(0)]),
                        center: glowCentre, startRadius: 0, endRadius: glowRadius
                    )
                )
            }

            // Fine tentacles sit behind, and stay faint on purpose.
            for index in 0..<jelly.fineCount {
                context.fill(
                    shaped(jelly.finePath(index, phase: phase)),
                    with: .color(.white.opacity(0.26))
                )
            }

            for index in 0..<jelly.armCount {
                let arm = shaped(jelly.armPath(index, phase: phase, pulse: pulse))
                let box = arm.boundingRect
                context.drawLayer { layer in
                    layer.addFilter(
                        .shadow(color: .black.opacity(0.30), radius: size * 0.024, y: size * 0.012)
                    )
                    layer.fill(arm, with: .linearGradient(
                        Gradient(colors: [.white, Self.shade]),
                        startPoint: CGPoint(x: box.midX, y: box.minY),
                        endPoint: CGPoint(x: box.midX, y: box.maxY)
                    ))
                }
            }

            let bell = shaped(jelly.bellPath(pulse: pulse))
            let bellBox = bell.boundingRect
            context.drawLayer { layer in
                layer.addFilter(
                    .shadow(color: .black.opacity(0.34), radius: size * 0.05, y: size * 0.018)
                )
                layer.fill(bell, with: .linearGradient(
                    Gradient(colors: [.white, Self.sheen, Self.shade]),
                    startPoint: CGPoint(x: bellBox.midX, y: bellBox.minY),
                    endPoint: CGPoint(x: bellBox.midX, y: bellBox.maxY)
                ))
            }

            // A lit core just inside the hem, brightening as the bell contracts.
            let coreRadius = canvasSize.width * 0.20
            let coreCentre = CGPoint(
                x: bellBox.midX,
                y: bellBox.maxY - bellBox.height * 0.34
            )
            context.drawLayer { layer in
                layer.clip(to: bell)
                layer.blendMode = .plusLighter
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: coreCentre.x - coreRadius, y: coreCentre.y - coreRadius,
                        width: coreRadius * 2, height: coreRadius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            Self.glow.opacity(0.10 + 0.16 * pulse), Self.glow.opacity(0),
                        ]),
                        center: coreCentre, startRadius: 0, endRadius: coreRadius
                    )
                )
            }
        }
    }

    private static let shade = Color(red: 0.760, green: 0.886, blue: 0.988)
    private static let sheen = Color(red: 0.930, green: 0.968, blue: 1.0)
    private static let glow = Color(red: 0.45, green: 0.80, blue: 1.0)
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.05, blue: 0.12),
                     Color(red: 0.06, green: 0.24, blue: 0.45)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        VStack(spacing: 40) {
            JellyfishMark(size: 200)
            JellyfishMark(size: 72)
        }
    }
}
