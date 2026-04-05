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

    /// Creates a community-rating pill (★ 8.5) with a yellow tint.
    public static func communityRating(_ rating: Double) -> MetadataPill? {
        guard rating > 0 else { return nil }
        let formatted =
            rating.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rating)
            : String(format: "%.1f", rating)
        return MetadataPill(icon: "star.fill", label: formatted, tint: .yellow)
    }

    /// Creates a critic-rating pill (❤ 92%) tinted green (≥ 60) or red (< 60).
    public static func criticRating(_ score: Double) -> MetadataPill? {
        guard score > 0 else { return nil }
        let tint: Color = score >= 60 ? .green : .red
        return MetadataPill(icon: "heart.fill", label: "\(Int(score))%", tint: tint)
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
}
