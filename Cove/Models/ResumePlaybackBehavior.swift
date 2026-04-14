import Foundation

/// Controls what happens when a user plays a video with existing progress.
enum ResumePlaybackBehavior: String, CaseIterable, Codable, Sendable {
    /// Always prompt the user to choose between resuming or starting over.
    case askEveryTime

    /// Automatically resume from where the user left off.
    case alwaysResume

    /// Always start from the beginning.
    case alwaysStartOver

    /// A user-facing label for this behavior.
    var label: String {
        switch self {
        case .askEveryTime: "Ask Every Time"
        case .alwaysResume: "Always Resume"
        case .alwaysStartOver: "Always Start Over"
        }
    }
}
