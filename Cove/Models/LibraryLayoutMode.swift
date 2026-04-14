import SwiftUI

/// Controls whether a library displays its items in a grid or a list.
enum LibraryLayoutMode: String, CaseIterable, Codable, Sendable {
    case grid
    case list

    /// A user-facing label for this layout mode.
    var label: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    /// The SF Symbol name representing this layout mode.
    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}
