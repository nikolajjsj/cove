// GenerateAppIcon.swift
//
// Draws the Cove app icon and writes every image the catalogue needs.
//
//     swiftc -O Tools/GenerateAppIcon.swift \
//            Cove/Components/Jellyfish/JellyfishGeometry.swift \
//            -o /tmp/genicon && /tmp/genicon Cove/Assets.xcassets/AppIcon.appiconset
//
// The mark is a jellyfish over deep water — a nod to the Jellyfin server that
// is actually holding the media. The curves come from JellyfishGeometry, the
// same file the animated onboarding mark draws from, so the icon and the first
// screen of the app can never drift apart.
//
// Contents.json is maintained by hand; this writes only the images.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S = JellyfishGeometry.reference
let CTR = CGPoint(x: S / 2, y: S / 2)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { rgb(v, v, v, a) }
func sgn(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

func context(_ size: CGFloat) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func save(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// Superellipse standing in for Apple's continuous-corner squircle.
func squircle(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...1440 {
        let t = CGFloat(i) / 1440 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let point = CGPoint(x: rect.midX + a * sgn(ct) * pow(abs(ct), 2 / n),
                            y: rect.midY + b * sgn(st) * pow(abs(st), 2 / n))
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func linear(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    ctx.drawLinearGradient(g, start: from, end: to,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], _ center: CGPoint, _ radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}

// MARK: - Variants

enum Variant { case light, dark, tinted }

func render(_ variant: Variant) -> CGImage {
    let ctx = context(S)

    switch variant {
    case .light:
        linear(ctx, [
            (0.00, rgb(0.016, 0.039, 0.098)),
            (0.42, rgb(0.031, 0.106, 0.231)),
            (0.76, rgb(0.043, 0.200, 0.384)),
            (1.00, rgb(0.063, 0.322, 0.510)),
        ], CGPoint(x: 0, y: S), CGPoint(x: 0, y: 0))
    case .dark:
        linear(ctx, [
            (0.00, rgb(0.008, 0.016, 0.043)),
            (0.45, rgb(0.016, 0.055, 0.122)),
            (1.00, rgb(0.027, 0.126, 0.224)),
        ], CGPoint(x: 0, y: S), CGPoint(x: 0, y: 0))
    case .tinted:
        // Grayscale: the system maps luminance onto the user's tint.
        linear(ctx, [(0.00, gray(0.055)), (0.50, gray(0.120)), (1.00, gray(0.235))],
               CGPoint(x: 0, y: S), CGPoint(x: 0, y: 0))
    }

    // Light pooling behind the creature.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    let glow: [(CGFloat, CGColor)]
    switch variant {
    case .light: glow = [(0, rgb(0.20, 0.62, 0.90, 0.36)), (0.55, rgb(0.12, 0.40, 0.72, 0.14)), (1, rgb(0.08, 0.26, 0.50, 0))]
    case .dark: glow = [(0, rgb(0.14, 0.44, 0.74, 0.28)), (0.55, rgb(0.08, 0.28, 0.54, 0.11)), (1, rgb(0.05, 0.18, 0.38, 0))]
    case .tinted: glow = [(0, gray(0.55, 0.24)), (0.55, gray(0.40, 0.10)), (1, gray(0.25, 0))]
    }
    radial(ctx, glow, CGPoint(x: S * 0.50, y: S * 0.44), S * 0.62)
    ctx.restoreGState()

    // Corner vignette — keeps the squircle's edges from glowing brighter than
    // the centre, which is what makes a flat gradient look printed on.
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    radial(ctx, [
        (0.00, gray(1.0, 0)),
        (0.62, gray(1.0, 0)),
        (1.00, variant == .tinted ? gray(0.55, 1) : rgb(0.35, 0.48, 0.62, 1)),
    ], CTR, S * 0.78)
    ctx.restoreGState()

    // JellyfishGeometry is laid out y-down, like SwiftUI. Flip once here.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    let jelly = JellyfishGeometry()
    let highlight = gray(1.0)
    let shade: CGColor
    switch variant {
    case .light: shade = rgb(0.760, 0.886, 0.988)
    case .dark: shade = rgb(0.596, 0.780, 0.945)
    case .tinted: shade = gray(0.74)
    }

    // Bioluminescence pooled under the bell.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    radial(ctx, variant == .tinted
           ? [(0, gray(0.70, 0.30)), (1, gray(0.30, 0))]
           : [(0, rgb(0.45, 0.80, 1.0, 0.34)), (1, rgb(0.15, 0.40, 0.70, 0))],
           CGPoint(x: jelly.hem.x, y: jelly.hem.y + 60), 360)
    ctx.restoreGState()

    for i in 0..<jelly.fineCount {
        ctx.addPath(jelly.finePath(i))
        ctx.setFillColor(gray(1, 0.26))
        ctx.fillPath()
    }

    for i in 0..<jelly.armCount {
        let path = jelly.armPath(i)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 34, color: rgb(0, 0.04, 0.13, 0.40))
        ctx.addPath(path); ctx.setFillColor(gray(1)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let box = path.boundingBox
        linear(ctx, [(0, highlight), (1, shade)],
               CGPoint(x: 0, y: box.maxY), CGPoint(x: 0, y: box.minY))
        ctx.restoreGState()
    }

    let bell = jelly.bellPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 52, color: rgb(0, 0.04, 0.13, 0.55))
    ctx.addPath(bell); ctx.setFillColor(gray(1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bell); ctx.clip()
    let box = bell.boundingBox
    linear(ctx, [
        (0, highlight),
        (0.62, variant == .tinted ? gray(0.93) : rgb(0.930, 0.968, 1.0)),
        (1, shade),
    ], CGPoint(x: 0, y: box.maxY), CGPoint(x: 0, y: box.minY))
    ctx.setBlendMode(.multiply)
    radial(ctx, [(0, variant == .tinted ? gray(0.72, 0.55) : rgb(0.48, 0.72, 0.92, 0.55)), (1, gray(1, 0))],
           CGPoint(x: jelly.hem.x, y: jelly.hem.y - 96), 208)
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - Output

/// macOS icons carry their own mask, margin, and contact shadow.
func macIcon(_ image: CGImage, _ size: Int) -> CGImage {
    let f = CGFloat(size)
    let ctx = context(f)
    let inset = f * 0.10
    let rect = CGRect(x: inset, y: inset + f * 0.015, width: f - inset * 2, height: f - inset * 2)
    let mask = squircle(in: rect)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -f * 0.012), blur: f * 0.035, color: gray(0, 0.35))
    ctx.addPath(mask); ctx.setFillColor(gray(0, 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(mask); ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    return ctx.makeImage()!
}

@main
enum GenerateAppIcon {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write(
                "usage: genicon <output directory>\n".data(using: .utf8)!)
            exit(2)
        }
        let outDir = CommandLine.arguments[1]

        let light = render(.light), dark = render(.dark), tinted = render(.tinted)
        save(light, "\(outDir)/AppIcon-1024.png")
        save(dark, "\(outDir)/AppIcon-Dark-1024.png")
        save(tinted, "\(outDir)/AppIcon-Tinted-1024.png")

        for (px, name) in [(16, "16"), (32, "16@2x"), (32, "32"), (64, "32@2x"),
                           (128, "128"), (256, "128@2x"), (256, "256"), (512, "256@2x"),
                           (512, "512"), (1024, "512@2x")] {
            save(macIcon(light, px), "\(outDir)/AppIcon-mac-\(name).png")
        }

        // Previews for eyeballing; intentionally not part of the catalogue.
        for (image, tag) in [(light, "light"), (dark, "dark"), (tinted, "tinted")] {
            for size in [512, 88] {
                let ctx = context(CGFloat(size))
                let rect = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
                ctx.addPath(squircle(in: rect)); ctx.clip()
                ctx.draw(image, in: rect)
                save(ctx.makeImage()!, "\(outDir)/preview-\(tag)-\(size).png")
            }
        }
        print("ok")
    }
}
