import Foundation

/// Jellyfin ticks ↔ seconds conversion helpers.
///
/// Jellyfin's API uses .NET "ticks" where 1 tick = 100 nanoseconds.
/// There are 10,000,000 ticks per second.
public enum JellyfinTicks {
    /// The number of Jellyfin ticks in one second.
    public static let perSecond: Double = 10_000_000.0

    /// Convert ticks to a `TimeInterval` (seconds).
    public static func toSeconds(_ ticks: Int64) -> TimeInterval {
        TimeInterval(ticks) / perSecond
    }

    /// Convert a `TimeInterval` (seconds) to ticks.
    public static func fromSeconds(_ seconds: TimeInterval) -> Int64 {
        Int64(seconds * perSecond)
    }
}
