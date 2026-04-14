import SwiftUI

/// Controls how compact the media item grid appears.
enum GridDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case regular
    case large

    /// A user-facing label for this density.
    var label: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    /// The minimum column width for the adaptive grid layout.
    var minimumWidth: CGFloat {
        switch self {
        case .compact: 60
        case .regular: 100
        case .large: 140
        }
    }

    /// The maximum column width for the adaptive grid layout.
    var maximumWidth: CGFloat {
        switch self {
        case .compact: 140
        case .regular: 200
        case .large: 240
        }
    }

    /// The spacing between grid items.
    var gridSpacing: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 16
        case .large: 20
        }
    }

    /// An adaptive set of grid columns sized for this density.
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumWidth, maximum: maximumWidth), spacing: gridSpacing)]
    }

    /// An SF Symbol name representing this density.
    var icon: String {
        switch self {
        case .compact: "square.grid.3x3"
        case .regular: "square.grid.2x2"
        case .large: "rectangle.grid.1x2"
        }
    }
}
