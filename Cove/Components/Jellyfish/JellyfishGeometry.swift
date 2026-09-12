import CoreGraphics
import Foundation

/// The curves behind the Cove jellyfish.
///
/// The app icon and the animated onboarding mark are the same creature, so the
/// geometry lives here and nowhere else — `Tools/GenerateAppIcon.swift` compiles
/// this file alongside itself rather than keeping its own copy, which is what
/// stops the two from drifting apart.
///
/// Everything is laid out in a 1024×1024 reference box with **y increasing
/// downwards**, matching SwiftUI. The icon generator flips its context once
/// before drawing; nothing else needs to think about it.
struct JellyfishGeometry {
    /// Centre of the bell's hem — the line the arms hang from.
    var hem = CGPoint(x: 512, y: 480)
    var bellWidth: CGFloat = 252
    var bellHeight: CGFloat = 200
    var lobes = 5
    var scallop: CGFloat = 46

    var armCount = 3
    var armSpread: CGFloat = 112
    var armLength: CGFloat = 300
    var armTopWidth: CGFloat = 94
    var armTipWidth: CGFloat = 20
    /// How far an arm's tip wanders from its root.
    var armSway: CGFloat = 50

    var fineCount = 4
    var fineLength: CGFloat = 372
    var fineWidth: CGFloat = 15

    static let reference: CGFloat = 1024

    /// The arms are not the same length; a rank of identical ones reads as a
    /// comb rather than a creature.
    private static let armScale: [CGFloat] = [0.88, 1.0, 0.93, 0.84]

    // MARK: - Bell

    /// A dome with a scalloped hem. The scallops dip below a continuous hem
    /// line rather than being cut out of it, so the silhouette stays solid at
    /// icon sizes instead of breaking into teeth.
    ///
    /// `pulse` runs 0…1 and drives the slow contraction a jellyfish swims with:
    /// the bell flattens and widens, and the arms trail slightly further.
    func bellPath(pulse: CGFloat = 0.5) -> CGPath {
        let squash = 1 - (pulse - 0.5) * 0.16
        let spread = 1 + (pulse - 0.5) * 0.09
        let rx = bellWidth * spread
        let ry = bellHeight * squash

        let path = CGMutablePath()
        path.move(to: CGPoint(x: hem.x - rx, y: hem.y))
        path.addCurve(
            to: CGPoint(x: hem.x + rx, y: hem.y),
            control1: CGPoint(x: hem.x - rx * 1.02, y: hem.y - ry * 1.58),
            control2: CGPoint(x: hem.x + rx * 1.02, y: hem.y - ry * 1.58)
        )
        for i in stride(from: lobes, through: 1, by: -1) {
            let toX = hem.x - rx + (2 * rx) * CGFloat(i - 1) / CGFloat(lobes)
            let midX = hem.x - rx + (2 * rx) * (CGFloat(i) - 0.5) / CGFloat(lobes)
            path.addQuadCurve(
                to: CGPoint(x: toX, y: hem.y),
                control: CGPoint(x: midX, y: hem.y + scallop)
            )
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Arms

    /// One oral arm. `phase` advances the travelling wave that runs down its
    /// length; hold it constant for a still pose.
    func armPath(_ index: Int, phase: CGFloat = 0, pulse: CGFloat = 0.5) -> CGPath {
        let middle = CGFloat(armCount - 1) / 2
        let offset = CGFloat(index) - middle
        let rootX = hem.x + offset * armSpread
        let length = armLength * Self.armScale[index % Self.armScale.count]
            * (1 + (pulse - 0.5) * 0.10)
        let seed = CGFloat(index) * 1.9

        var points: [CGPoint] = []
        var widths: [CGFloat] = []
        let steps = 96
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            // Sway grows towards the tip, so the root stays anchored under the
            // bell while the end drifts.
            let wave = sin(t * 2.7 - phase + seed) * armSway * t
            let flare = offset * 36 * t
            points.append(CGPoint(x: rootX + wave + flare, y: hem.y - 26 + t * length))
            widths.append(armTipWidth + (armTopWidth - armTipWidth) * pow(1 - t, 0.95))
        }
        return Self.ribbon(points, widths)
    }

    /// The long thin tentacles behind the arms. They carry the movement at
    /// large sizes and disappear at small ones, which is the point of them.
    func finePath(_ index: Int, phase: CGFloat = 0) -> CGPath {
        let spread = CGFloat(index) / CGFloat(max(1, fineCount - 1)) * 2 - 1
        let rootX = hem.x + spread * bellWidth * 0.84
        let seed = CGFloat(index) * 1.4

        var points: [CGPoint] = []
        var widths: [CGFloat] = []
        let steps = 96
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let wave = sin(t * 3.7 - phase * 1.25 + seed) * 58 * t
            points.append(CGPoint(x: rootX + wave + spread * 58 * t,
                                  y: hem.y - 40 + t * fineLength))
            widths.append(3 + (fineWidth - 3) * pow(1 - t, 1.2))
        }
        return Self.ribbon(points, widths)
    }

    // MARK: - Ribbon

    /// Outline of a band of varying width laid along a centreline.
    private static func ribbon(_ points: [CGPoint], _ widths: [CGFloat]) -> CGPath {
        func normal(at index: Int) -> CGPoint {
            let before = points[max(0, index - 1)]
            let after = points[min(points.count - 1, index + 1)]
            let dx = after.x - before.x
            let dy = after.y - before.y
            let length = max(0.0001, sqrt(dx * dx + dy * dy))
            return CGPoint(x: -dy / length, y: dx / length)
        }

        let path = CGMutablePath()
        for index in points.indices {
            let n = normal(at: index)
            let half = widths[index] / 2
            let point = CGPoint(x: points[index].x + n.x * half,
                                y: points[index].y + n.y * half)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        for index in points.indices.reversed() {
            let n = normal(at: index)
            let half = widths[index] / 2
            path.addLine(to: CGPoint(x: points[index].x - n.x * half,
                                     y: points[index].y - n.y * half))
        }
        path.closeSubpath()
        return path
    }
}
