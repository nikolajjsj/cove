import Foundation

/// Shared time formatting utilities used across the app's UI.
enum TimeFormatting {
    /// Formats a duration as "1h 23m" or "45m" for metadata display.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0m" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Formats a playback position as "1:23:45" or "23:45".
    static func playbackPosition(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", mins)):\(String(format: "%02d", secs))"
        }
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
