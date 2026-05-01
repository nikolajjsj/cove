import Foundation
import Models

/// Abstracts the system now-playing / remote-command integration
/// (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) so that
/// `AudioPlaybackManager` can be unit-tested without the real media controls.
///
/// The production implementation is ``NowPlayingService``.
/// Tests can supply a lightweight mock that records calls instead of touching
/// the system singleton.
@MainActor
public protocol NowPlayingProvider: AnyObject {

    // MARK: - Remote Command Callbacks

    /// Called when the user taps Play on the lock screen / Control Center.
    var onPlay: (@MainActor () -> Void)? { get set }

    /// Called when the user taps Pause.
    var onPause: (@MainActor () -> Void)? { get set }

    /// Called when the user taps Next Track.
    var onNext: (@MainActor () -> Void)? { get set }

    /// Called when the user taps Previous Track.
    var onPrevious: (@MainActor () -> Void)? { get set }

    /// Called when the user scrubs to a new position.
    var onSeek: (@MainActor (TimeInterval) -> Void)? { get set }

    /// Called when the user toggles play/pause (e.g. via AirPods double-tap).
    var onTogglePlayPause: (@MainActor () -> Void)? { get set }

    /// Called when the user taps the favourite (heart) button on the lock screen.
    var onToggleFavorite: (@MainActor () -> Void)? { get set }

    // MARK: - Lifecycle

    /// Register remote-command targets. Call once during setup.
    func setup()

    /// Remove all remote-command targets and clear now-playing info.
    func teardown()

    // MARK: - Now Playing Info Updates

    /// Set the full now-playing metadata for a new track.
    ///
    /// - Parameters:
    ///   - track: The track whose metadata should be displayed.
    ///   - isPlaying: Whether playback is active.
    ///   - currentTime: Elapsed playback time in seconds.
    ///   - duration: Total duration in seconds.
    ///   - artworkURL: An optional URL for asynchronous artwork loading.
    func updateNowPlaying(
        track: Track,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        artworkURL: URL?
    )

    /// Update only the playback-state portion of the existing now-playing info
    /// (elapsed time, playback rate, duration). This is called on a periodic
    /// timer and should be lightweight.
    func updatePlaybackState(
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval
    )

    /// Update the active state of the favourite (heart) button on the lock screen.
    /// Call this whenever the favourite state of the current track changes.
    func updateFavoriteState(isFavorite: Bool)
}
