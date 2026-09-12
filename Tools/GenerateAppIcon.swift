// GenerateAppIcon.swift
//
// Draws the Cove app icon and writes every image the catalogue needs.
//
//     swift Tools/GenerateAppIcon.swift Cove/Assets.xcassets/AppIcon.appiconset
//
// The mark is a tapered crescent — the sheltering arm of a cove, and the C of
// Cove — cradling a play triangle, over deep water. Keeping the icon as code
// rather than a flattened export means the proportions, the palette, and the
// light/dark/tinted variants stay editable and stay consistent with one
// another. Contents.json is maintained by hand; this writes only the images.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { rgb(v, v, v, a) }

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

func sgn(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

/// Superellipse standing in for Apple's continuous-corner squircle.
func squircle(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width/2, b = rect.height/2
    for i in 0...1440 {
        let t = CGFloat(i) / 1440 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * sgn(ct) * pow(abs(ct), 2/n)
        let y = rect.midY + b * sgn(st) * pow(abs(st), 2/n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func linear(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    ctx.drawLinearGradient(g, start: from, end: to,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], _ center: CGPoint, _ r0: CGFloat, _ r1: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: r0,
                           endCenter: center, endRadius: r1, options: [])
}

// MARK: - The mark

/// A band that tapers to a point at both ends — the sheltering arm of a cove,
/// and the C of Cove. Thickest at `back`, vanishing at ±`halfSweep`.
func crescent(center: CGPoint, outer: CGFloat, maxWidth: CGFloat,
              back: CGFloat, halfSweep: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = 600
    func angle(_ i: Int) -> (CGFloat, CGFloat) {
        let d = -halfSweep + (2*halfSweep) * CGFloat(i)/CGFloat(steps)
        return (back + d, d)
    }
    for i in 0...steps {
        let (a, _) = angle(i)
        let pt = CGPoint(x: center.x + outer*cos(a), y: center.y + outer*sin(a))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    for i in stride(from: steps, through: 0, by: -1) {
        let (a, d) = angle(i)
        let t = min(1, abs(d) / halfSweep)
        let r = outer - maxWidth * sqrt(max(0, 1 - t*t))
        p.addLine(to: CGPoint(x: center.x + r*cos(a), y: center.y + r*sin(a)))
    }
    p.closeSubpath()
    return p
}

func roundedPolygon(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    p.move(to: CGPoint(x: (pts[0].x + pts[1].x)/2, y: (pts[0].y + pts[1].y)/2))
    for i in 1...n {
        p.addArc(tangent1End: pts[i % n], tangent2End: pts[(i+1) % n], radius: radius)
    }
    p.closeSubpath()
    return p
}

func playMark(center: CGPoint, radius: CGFloat, corner: CGFloat) -> CGPath {
    roundedPolygon((0..<3).map { i in
        let a = CGFloat(i) * 2 * .pi / 3
        return CGPoint(x: center.x + radius*cos(a), y: center.y + radius*sin(a))
    }, radius: corner)
}

// The group is shifted right so the crescent's mass and the play mark balance
// around the optical centre rather than the geometric one.
let groupDX: CGFloat = 48
let markCenter = CGPoint(x: S/2 + groupDX, y: S/2)

var crescentPath: CGPath {
    crescent(center: markCenter, outer: 330, maxWidth: 96,
             back: .pi, halfSweep: 122 * .pi/180)
}
var playPath: CGPath {
    playMark(center: CGPoint(x: markCenter.x + 10, y: markCenter.y), radius: 150, corner: 30)
}

// MARK: - Shape treatment

/// Fills `path` with a top-lit gradient and drops it onto the background.
/// Depth comes from the shadow and the gradient alone — an edge bevel reads as
/// emboss at 1024 and as dirt at 88.
func sculpt(_ ctx: CGContext, _ path: CGPath,
            top: CGColor, bottom: CGColor,
            rim: CGColor, occlusion: CGColor,
            shadow: CGColor) {
    let box = path.boundingBox

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 52, color: shadow)
    ctx.addPath(path); ctx.setFillColor(gray(1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    linear(ctx, [(0, top), (1, bottom)],
           CGPoint(x: 0, y: box.maxY), CGPoint(x: 0, y: box.minY))
    ctx.restoreGState()
    _ = (rim, occlusion)
}

// MARK: - Variants

enum Variant { case light, dark, tinted }

func render(_ variant: Variant) -> CGImage {
    let ctx = context(S)
    let full = CGRect(x: 0, y: 0, width: S, height: S)

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
        linear(ctx, [
            (0.00, gray(0.055)),
            (0.50, gray(0.120)),
            (1.00, gray(0.235)),
        ], CGPoint(x: 0, y: S), CGPoint(x: 0, y: 0))
    }

    // Light pooling behind the mark.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    let glow: [(CGFloat, CGColor)]
    switch variant {
    case .light: glow = [(0, rgb(0.20, 0.62, 0.90, 0.34)), (0.55, rgb(0.12, 0.40, 0.72, 0.13)), (1, rgb(0.08, 0.26, 0.50, 0))]
    case .dark: glow = [(0, rgb(0.14, 0.44, 0.74, 0.26)), (0.55, rgb(0.08, 0.28, 0.54, 0.10)), (1, rgb(0.05, 0.18, 0.38, 0))]
    case .tinted: glow = [(0, gray(0.55, 0.22)), (0.55, gray(0.40, 0.09)), (1, gray(0.25, 0))]
    }
    radial(ctx, glow, CGPoint(x: S*0.54, y: S*0.46), 0, S*0.60)
    ctx.restoreGState()

    // Corner vignette — keeps the squircle's edges from glowing brighter than
    // the centre, which is what makes a flat gradient look printed on.
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    radial(ctx, [
        (0.00, gray(1.0, 0)),
        (0.62, gray(1.0, 0)),
        (1.00, variant == .tinted ? gray(0.55, 1) : rgb(0.35, 0.48, 0.62, 1)),
    ], CGPoint(x: S/2, y: S/2), 0, S*0.78)
    ctx.restoreGState()
    _ = full

    let cres = crescentPath
    let play = playPath

    switch variant {
    case .light:
        sculpt(ctx, cres,
               top: gray(1.0), bottom: rgb(0.820, 0.912, 0.988),
               rim: gray(1.0, 0.85), occlusion: rgb(0.15, 0.38, 0.60, 0.22),
               shadow: rgb(0, 0.043, 0.129, 0.55))
        sculpt(ctx, play,
               top: gray(1.0), bottom: rgb(0.855, 0.933, 0.996),
               rim: gray(1.0, 0.85), occlusion: rgb(0.15, 0.38, 0.60, 0.20),
               shadow: rgb(0, 0.043, 0.129, 0.50))
    case .dark:
        sculpt(ctx, cres,
               top: rgb(0.914, 0.957, 1.0), bottom: rgb(0.596, 0.780, 0.945),
               rim: gray(1.0, 0.7), occlusion: rgb(0.08, 0.22, 0.40, 0.30),
               shadow: rgb(0, 0.02, 0.07, 0.65))
        sculpt(ctx, play,
               top: rgb(0.925, 0.961, 1.0), bottom: rgb(0.639, 0.808, 0.957),
               rim: gray(1.0, 0.7), occlusion: rgb(0.08, 0.22, 0.40, 0.28),
               shadow: rgb(0, 0.02, 0.07, 0.6))
    case .tinted:
        sculpt(ctx, cres,
               top: gray(1.0), bottom: gray(0.78),
               rim: gray(1.0, 0.8), occlusion: gray(0.35, 0.25),
               shadow: gray(0.0, 0.55))
        sculpt(ctx, play,
               top: gray(1.0), bottom: gray(0.82),
               rim: gray(1.0, 0.8), occlusion: gray(0.35, 0.22),
               shadow: gray(0.0, 0.5))
    }

    return ctx.makeImage()!
}

// MARK: - Output

let outDir = CommandLine.arguments[1]

func scaled(_ img: CGImage, _ size: Int) -> CGImage {
    let c = context(CGFloat(size))
    c.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    return c.makeImage()!
}

/// macOS icons carry their own mask, margin, and contact shadow.
func macIcon(_ img: CGImage, _ size: Int) -> CGImage {
    let f = CGFloat(size)
    let c = context(f)
    let inset = f * 0.10
    let rect = CGRect(x: inset, y: inset + f*0.015, width: f - inset*2, height: f - inset*2)
    let mask = squircle(in: rect)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -f*0.012), blur: f*0.035, color: gray(0, 0.35))
    c.addPath(mask); c.setFillColor(gray(0, 1)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(mask); c.clip()
    c.draw(img, in: rect)
    c.restoreGState()
    return c.makeImage()!
}

let light = render(.light), dark = render(.dark), tinted = render(.tinted)

save(light, "\(outDir)/AppIcon-1024.png")
save(dark, "\(outDir)/AppIcon-Dark-1024.png")
save(tinted, "\(outDir)/AppIcon-Tinted-1024.png")

for (px, name) in [(16, "16"), (32, "16@2x"), (32, "32"), (64, "32@2x"),
                   (128, "128"), (256, "128@2x"), (256, "256"), (512, "256@2x"),
                   (512, "512"), (1024, "512@2x")] {
    save(macIcon(light, px), "\(outDir)/AppIcon-mac-\(name).png")
}

// Previews
for (img, tag) in [(light, "light"), (dark, "dark"), (tinted, "tinted")] {
    for size in [512, 180, 88] {
        let c = context(CGFloat(size))
        let r = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
        c.addPath(squircle(in: r)); c.clip()
        c.draw(img, in: r)
        save(c.makeImage()!, "\(outDir)/preview-\(tag)-\(size).png")
    }
}
print("ok")
