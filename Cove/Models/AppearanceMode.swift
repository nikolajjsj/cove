import SwiftUI

/// Controls the app's color scheme preference.
enum AppearanceMode: String, CaseIterable, Codable {
    case system
    case light
    case dark

    /// A user-facing label for this appearance mode.
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The SF Symbol name representing this appearance mode.
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// The SwiftUI color scheme corresponding to this mode.
    ///
    /// Returns `nil` for `.system`, which tells SwiftUI to follow
    /// the device's current appearance setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
