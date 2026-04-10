import Foundation

/// The watched/played filter state for a media library.
enum WatchedFilter: String, Hashable, CaseIterable {
    case all
    case unwatched
    case watched

    var label: String {
        switch self {
        case .all: "All"
        case .unwatched: "Unwatched"
        case .watched: "Watched"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .unwatched: "eye.slash"
        case .watched: "eye"
        }
    }
}
