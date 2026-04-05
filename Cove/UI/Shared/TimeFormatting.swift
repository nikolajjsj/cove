import Foundation

/// Shared time formatting utilities used across the app's UI.
enum TimeFormatting {

    // MARK: - Compact Duration ("1h 23m" / "45m")

    /// Formats a duration as "1h 23m" or "45m" for compact metadata display.
    ///
    /// Used in movie detail subtitle lines and similar tight layouts.
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

    // MARK: - Long Duration ("1 hr 23 min" / "45 min")

    /// Formats a duration with spelled-out units: "1 hr 23 min" or "45 min".
    ///
    /// Used for album totals, playlist totals, and episode runtimes where
    /// there is more horizontal space.
    static func longDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0 min" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }

    // MARK: - Playback Position ("1:23:45" / "23:45")

    /// Formats a playback position as "H:MM:SS" or "M:SS".
    ///
    /// Includes an hours component when the value is ≥ 3600 seconds.
    /// Used for video player scrubbers, audio player elapsed/remaining, and
    /// anywhere a precise timestamp is shown.
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

    // MARK: - Track Time ("3:45")

    /// Formats a track or short media duration as "M:SS".
    ///
    /// Unlike ``playbackPosition(_:)``, this always uses the "M:SS" format even
    /// for durations over an hour (e.g. "65:23"). Returns an empty string for
    /// zero or negative values, which is convenient for hiding duration labels
    /// on tracks with unknown length.
    static func trackTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
