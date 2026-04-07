import SwiftUI

/// A lightweight model representing a single metadata pill / chip.
///
/// Used by ``MetadataPillsView`` to render a horizontally-scrolling row of
/// capsule-shaped metadata indicators (ratings, genres, play counts, etc.).
///
/// ```swift
/// let pills: [MetadataPill] = [
///     MetadataPill(icon: "star.fill", label: "8.5", tint: .yellow),
///     MetadataPill(icon: "heart.fill", label: "92%", tint: .green),
///     MetadataPill(label: "Action"),
/// ]
/// ```
public struct MetadataPill: Hashable, Sendable {

    /// An optional SF Symbol name displayed before the label.
    public let icon: String?

    /// The text content of the pill.
    public let label: String

    /// An optional tint applied to both the icon and label.
    /// When `nil`, the pill uses `.secondary` foreground style.
    public let tint: Color?

    /// Creates a metadata pill.
    ///
    /// - Parameters:
    ///   - icon: An optional SF Symbol name. Pass `nil` for text-only pills.
    ///   - label: The text content of the pill.
    ///   - tint: An optional tint color. Defaults to `nil` (`.secondary`).
    public init(icon: String? = nil, label: String, tint: Color? = nil) {
        self.icon = icon
        self.label = label
        self.tint = tint
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(icon)
        hasher.combine(label)
    }

    public static func == (lhs: MetadataPill, rhs: MetadataPill) -> Bool {
        lhs.icon == rhs.icon && lhs.label == rhs.label
    }
}

// MARK: - Common Factory Methods

extension MetadataPill {

    /// Creates a community-rating pill (★ 8.5 or ★ IMDb 8.5) with a yellow tint.
    /// - Parameters:
    ///   - rating: The community rating value.
    ///   - source: An optional source label (e.g. "IMDb") prepended to the rating.
    public static func communityRating(_ rating: Double, source: String? = nil) -> MetadataPill? {
        guard rating > 0 else { return nil }
        let formatted =
            rating.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rating)
            : String(format: "%.1f", rating)
        let label = source.map { "\($0) \(formatted)" } ?? formatted
        return MetadataPill(icon: "star.fill", label: label, tint: .yellow)
    }

    /// Creates a critic-rating pill (❤ 92% or ❤ RT 92%) tinted green (≥ 60) or red (< 60).
    /// - Parameters:
    ///   - score: The critic rating percentage.
    ///   - source: An optional source label (e.g. "RT") prepended to the score.
    public static func criticRating(_ score: Double, source: String? = nil) -> MetadataPill? {
        guard score > 0 else { return nil }
        let tint: Color = score >= 60 ? .green : .red
        let label = source.map { "\($0) \(Int(score))%" } ?? "\(Int(score))%"
        return MetadataPill(icon: "heart.fill", label: label, tint: tint)
    }

    /// Creates a "Played" pill with a green checkmark.
    public static var played: MetadataPill {
        MetadataPill(icon: "checkmark.circle.fill", label: "Played", tint: .green)
    }

    /// Creates a play-count pill (↻ Played 3×).
    public static func playCount(_ count: Int) -> MetadataPill? {
        guard count > 1 else { return nil }
        return MetadataPill(icon: "arrow.counterclockwise", label: "Played \(count)×", tint: nil)
    }

    /// Creates a genre pill with no icon.
    public static func genre(_ name: String) -> MetadataPill {
        MetadataPill(label: name)
    }

    /// Creates an item-count pill (e.g. "5 items").
    public static func itemCount(_ count: Int) -> MetadataPill {
        let label = "\(count) \(count == 1 ? "item" : "items")"
        return MetadataPill(icon: "rectangle.stack.fill", label: label, tint: nil)
    }

    /// Creates a video resolution pill (e.g. "4K", "1080p").
    public static func resolution(width: Int) -> MetadataPill? {
        let label: String
        if width >= 3840 {
            label = "4K"
        } else if width >= 1920 {
            label = "1080p"
        } else if width >= 1280 {
            label = "720p"
        } else if width > 0 {
            label = "SD"
        } else {
            return nil
        }
        return MetadataPill(icon: "tv", label: label, tint: nil)
    }

    /// Creates an HDR pill when HDR content is detected.
    public static func hdr(videoRange: String?, videoRangeType: String?) -> MetadataPill? {
        // Prefer the more specific videoRangeType
        if let rangeType = videoRangeType?.lowercased() {
            switch rangeType {
            case "dovi", "dolbyvision":
                return MetadataPill(icon: "sparkles", label: "Dolby Vision", tint: .purple)
            case "hdr10plus":
                return MetadataPill(icon: "sparkles", label: "HDR10+", tint: .orange)
            case "hdr10":
                return MetadataPill(icon: "sparkles", label: "HDR10", tint: .orange)
            default:
                break
            }
        }
        // Fall back to videoRange
        if let range = videoRange?.uppercased(), range == "HDR" {
            return MetadataPill(icon: "sparkles", label: "HDR", tint: .orange)
        }
        return nil
    }

    /// Creates an audio channels pill (e.g. "5.1", "7.1", "Stereo").
    public static func audioChannels(_ channels: Int) -> MetadataPill? {
        let label: String
        switch channels {
        case 8: label = "7.1"
        case 6: label = "5.1"
        case 2: label = "Stereo"
        case 1: label = "Mono"
        default: return nil
        }
        return MetadataPill(icon: "speaker.wave.2.fill", label: label, tint: nil)
    }

    /// Creates the standard community-rating and critic-rating pills with
    /// source branding (e.g. "IMDb", "RT") when provider IDs are available.
    ///
    /// This consolidates the shared rating-pill logic used by movie and series
    /// detail views.
    ///
    /// - Parameters:
    ///   - communityRating: The community rating value (e.g. 8.5).
    ///   - criticRating: The critic rating percentage (e.g. 92).
    ///   - hasImdb: Whether an IMDb provider ID is present (brands the rating as "IMDb").
    /// - Returns: An array of 0–2 pills depending on which ratings are non-zero.
    public static func ratingPills(
        communityRating: Double?,
        criticRating: Double?,
        hasImdb: Bool = false
    ) -> [MetadataPill] {
        var pills: [MetadataPill] = []

        let ratingSource: String? = hasImdb ? "IMDb" : nil
        if let pill = MetadataPill.communityRating(communityRating ?? 0, source: ratingSource) {
            pills.append(pill)
        }

        let criticSource: String? = (criticRating ?? 0) > 0 ? "RT" : nil
        if let pill = MetadataPill.criticRating(criticRating ?? 0, source: criticSource) {
            pills.append(pill)
        }

        return pills
    }
}
