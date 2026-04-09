import Foundation

// MARK: - DownloadAction

/// Actions that can be performed on a download item from the UI.
enum DownloadAction: Sendable {
    case pause
    case resume
    case retry
    case delete
    case play
}
