import Foundation

/// Options for the sleep timer that pauses playback after a duration or at the end of the current track.
public enum SleepTimerMode: Sendable, Equatable {
    /// Pause playback after the specified number of minutes.
    case minutes(Int)  // 5, 10, 15, 30, 45, 60
    /// Pause playback when the current track finishes.
    case endOfTrack
}
