#if canImport(CoreGraphics)
    import CoreGraphics
    import SwiftUI

    /// Extracts dominant colors from a CGImage by downsampling to 10×10 and
    /// bucketing pixels by HSB values.
    ///
    /// Usage:
    /// ```swift
    /// if let cgImage = uiImage.cgImage {
    ///     let result = DominantColorExtractor.extractColors(from: cgImage)
    ///     // result.primary is the dominant Color
    ///     // result.isLight indicates if the color is light (luminance > 0.5)
    /// }
    /// ```
    public enum DominantColorExtractor {

        /// The result of a color extraction.
        public struct ExtractionResult: Sendable {
            /// The dominant color found in the image.
            public let primary: Color
            /// A darkened variant of the primary color for gradient bottoms.
            public let darkened: Color
            /// Whether the dominant color is light (luminance > 0.5).
            public let isLight: Bool
        }

        /// Default fallback when extraction fails or no artwork is available.
        public static let fallback = ExtractionResult(
            primary: Color.gray.opacity(0.4),
            darkened: Color.gray.opacity(0.15),
            isLight: false
        )

        /// Extracts the dominant color from a CGImage.
        ///
        /// - Parameter image: The source image (any size — will be downsampled).
        /// - Returns: An `ExtractionResult` with the dominant color, a darkened variant, and luminance info.
        public static func extractColors(from image: CGImage) -> ExtractionResult {
            let width = 10
            let height = 10
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

            guard
                let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return fallback
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Collect pixel colors as HSB
            var buckets: [HSBBucket: Int] = [:]

            for i in 0..<(width * height) {
                let offset = i * bytesPerPixel
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0

                var hue: CGFloat = 0
                var sat: CGFloat = 0
                var bri: CGFloat = 0

                #if canImport(UIKit)
                    UIColor(red: r, green: g, blue: b, alpha: 1).getHue(
                        &hue, saturation: &sat, brightness: &bri, alpha: nil)
                #elseif canImport(AppKit)
                    NSColor(red: r, green: g, blue: b, alpha: 1).getHue(
                        &hue, saturation: &sat, brightness: &bri, alpha: nil)
                #endif

                // Skip near-white and near-black pixels
                guard bri > 0.05 && bri < 0.95 else { continue }
                // Skip very low saturation (grays)
                guard sat > 0.1 else { continue }

                // Bucket into coarse bins (12 hue × 4 sat × 4 bri = 192 buckets)
                let bucket = HSBBucket(
                    hue: Int(hue * 12),
                    saturation: Int(sat * 4),
                    brightness: Int(bri * 4)
                )
                buckets[bucket, default: 0] += 1
            }

            // Find the most frequent bucket
            guard let topBucket = buckets.max(by: { $0.value < $1.value })?.key else {
                return fallback
            }

            // Convert bucket center back to a color
            let h = (CGFloat(topBucket.hue) + 0.5) / 12.0
            let s = (CGFloat(topBucket.saturation) + 0.5) / 4.0
            let bri = (CGFloat(topBucket.brightness) + 0.5) / 4.0

            let primary = Color(hue: Double(h), saturation: Double(s), brightness: Double(bri))
            let darkened = Color(
                hue: Double(h), saturation: Double(min(s + 0.1, 1.0)),
                brightness: Double(max(bri * 0.4, 0.08)))

            // Calculate luminance from the bucket center
            let luminance = brightnessToLuminance(h: h, s: s, b: bri)

            return ExtractionResult(
                primary: primary,
                darkened: darkened,
                isLight: luminance > 0.5
            )
        }

        // MARK: - Private

        private struct HSBBucket: Hashable {
            let hue: Int
            let saturation: Int
            let brightness: Int
        }

        /// Approximate luminance from HSB values using the standard formula.
        private static func brightnessToLuminance(h: CGFloat, s: CGFloat, b: CGFloat) -> CGFloat {
            // Convert HSB to RGB for luminance calculation
            #if canImport(UIKit)
                let color = UIColor(hue: h, saturation: s, brightness: b, alpha: 1)
                var r: CGFloat = 0
                var g: CGFloat = 0
                var blue: CGFloat = 0
                color.getRed(&r, green: &g, blue: &blue, alpha: nil)
                return 0.299 * r + 0.587 * g + 0.114 * blue
            #elseif canImport(AppKit)
                let color = NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
                var r: CGFloat = 0
                var g: CGFloat = 0
                var blue: CGFloat = 0
                color.getRed(&r, green: &g, blue: &blue, alpha: nil)
                return 0.299 * r + 0.587 * g + 0.114 * blue
            #else
                return b * (1 - s * 0.5)  // rough approximation
            #endif
        }
    }
#endif
