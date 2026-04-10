import Defaults
import SwiftUI

/// Size options for subtitle text.
enum SubtitleSize: String, CaseIterable, Codable, Defaults.Serializable {
    case small
    case medium
    case large
    case extraLarge

    var font: Font {
        switch self {
        case .small: .subheadline.weight(.semibold)
        case .medium: .body.weight(.semibold)
        case .large: .title3.weight(.semibold)
        case .extraLarge: .title2.weight(.semibold)
        }
    }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

/// Background style options for subtitle text.
enum SubtitleBackground: String, CaseIterable, Codable, Defaults.Serializable {
    case none
    case outline
    case dropShadow
    case semiTransparent
    case opaque

    var displayName: String {
        switch self {
        case .none: "None"
        case .outline: "Outline"
        case .dropShadow: "Drop Shadow"
        case .semiTransparent: "Semi-Transparent"
        case .opaque: "Opaque Background"
        }
    }
}

/// Color options for subtitle text.
enum SubtitleColor: String, CaseIterable, Codable, Defaults.Serializable {
    case white
    case yellow
    case green
    case cyan

    var color: Color {
        switch self {
        case .white: .white
        case .yellow: .yellow
        case .green: .green
        case .cyan: .cyan
        }
    }

    var displayName: String {
        switch self {
        case .white: "White"
        case .yellow: "Yellow"
        case .green: "Green"
        case .cyan: "Cyan"
        }
    }
}
