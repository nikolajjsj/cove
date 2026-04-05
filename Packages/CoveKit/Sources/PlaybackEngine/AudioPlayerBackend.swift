import Foundation
import Models

/// Abstracts the audio player implementation (e.g. `AVQueuePlayer`) so that
/// ``AudioPlaybackManager`` can be unit-tested without a real media pipeline.
///
/// The backend manages a sequential queue of audio items. Items are enqueued
/// by URL and identified by opaque tokens for lifecycle tracking.
///
/// ## Token-Based Item Tracking
///
/// Every call to ``enqueue(url:)`` returns an opaque `AnyHashable` token.
/// When an item finishes playing, the backend fires ``onItemDidFinish`` with
/// that same token. This lets `AudioPlaybackManager` map finished items back
/// to their `Track` without depending on `AVPlayerItem`.
///
/// ## Threading
///
/// All members are `@MainActor`-isolated. Callbacks are guaranteed to fire
/// on the main actor.
@MainActor
public protocol AudioPlayerBackend: AnyObject {

    // MARK: - Playback Control

    /// Start or resume playback of the current item in the queue.
    func play()

    /// Pause playback.
    func pause()

    /// Seek the current item to a specific time.
    ///
    /// - Parameters:
    ///   - seconds: The target position in seconds.
    ///   - completion: Called with `true` when the seek completes successfully,
    ///     or `false` if it was interrupted / failed. May be called on any thread.
    func seek(to seconds: TimeInterval, completion: @escaping @Sendable (Bool) -> Void)

    // MARK: - Queue Management

    /// Remove all items from the playback queue and stop playback.
    func clearQueue()

    /// Append an audio item to the end of the playback queue.
    ///
    /// Items play sequentially in the order they were enqueued.
    ///
    /// - Parameter url: The streaming URL for the audio item.
    /// - Returns: An opaque token identifying this item. The same token is
    ///   passed to ``onItemDidFinish`` when the item reaches its end.
    @discardableResult
    func enqueue(url: URL) -> AnyHashable

    // MARK: - State

    /// The duration of the currently-playing item in seconds,
    /// or `nil` if unknown or no item is loaded.
    var currentItemDuration: TimeInterval? { get }

    /// The token of the currently-playing item, or `nil` if the queue is empty.
    ///
    /// Used after a gapless transition to determine whether the backend already
    /// advanced to the next pre-loaded item.
    var currentItemToken: AnyHashable? { get }

    // MARK: - Event Callbacks

    /// Called periodically (~0.5 s) with the current playback position in seconds.
    ///
    /// Set by ``AudioPlaybackManager`` during setup. The backend must call this
    /// on the main actor.
    var onTimeUpdate: (@MainActor (TimeInterval) -> Void)? { get set }

    /// Called when the effective play/pause state changes due to external causes
    /// (e.g. audio stalling, interruption, AirPlay transfer).
    ///
    /// - Parameter isPlaying: `true` if the player resumed, `false` if it paused.
    var onPlayingChanged: (@MainActor (_ isPlaying: Bool) -> Void)? { get set }

    /// Called when an enqueued item finishes playing to its natural end.
    ///
    /// - Parameter token: The token returned by ``enqueue(url:)`` for this item.
    var onItemDidFinish: (@MainActor (_ token: AnyHashable) -> Void)? { get set }
}
