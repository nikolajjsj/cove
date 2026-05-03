import AVFoundation
import Foundation

/// Concrete ``AudioPlayerBackend`` implementation backed by `AVQueuePlayer`.
///
/// Handles periodic time observation, KVO on player rate, and end-of-item
/// notifications, bridging them into the protocol's callback closures.
///
/// This is the default backend used by ``AudioPlaybackManager`` in production.
@MainActor
public final class AVQueuePlayerBackend: AudioPlayerBackend {

    // MARK: - Internal Player

    private let player = AVQueuePlayer()

    // MARK: - Observers & Tasks

    /// Periodic time observer token (must be removed in deinit).
    @ObservationIgnored private nonisolated(unsafe) var timeObserverToken: Any?

    /// KVO observation on `player.rate` for detecting external play/pause.
    @ObservationIgnored private nonisolated(unsafe) var rateObservation: NSKeyValueObservation?

    /// Async task listening for `AVPlayerItemDidPlayToEndTime` notifications.
    @ObservationIgnored private nonisolated(unsafe) var endOfItemTask: Task<Void, Never>?

    /// Async task listening for `AVPlayerItemFailedToPlayToEndTime` notifications.
    @ObservationIgnored private nonisolated(unsafe) var failedItemTask: Task<Void, Never>?

    // MARK: - Token Tracking

    /// Maps each `AVPlayerItem` to the opaque token returned by `enqueue(url:)`.
    private var itemToToken: [AVPlayerItem: AnyHashable] = [:]

    /// Monotonically-increasing counter used to generate unique tokens.
    private var nextTokenID: Int = 0

    // MARK: - AudioPlayerBackend Callbacks

    public var onTimeUpdate: (@MainActor (TimeInterval) -> Void)?
    public var onPlayingChanged: (@MainActor (_ isPlaying: Bool) -> Void)?
    public var onItemDidFinish: (@MainActor (_ token: AnyHashable) -> Void)?

    // MARK: - Init / Deinit

    public init() {
        setupTimeObserver()
        setupRateObserver()
        setupEndOfItemObserver()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        rateObservation?.invalidate()
        endOfItemTask?.cancel()
        failedItemTask?.cancel()
    }

    // MARK: - AudioPlayerBackend — Playback Control

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to seconds: TimeInterval, completion: @escaping @Sendable (Bool) -> Void) {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: cmTime, completionHandler: completion)
    }

    // MARK: - AudioPlayerBackend — Queue Management

    public func clearQueue() {
        player.removeAllItems()
        itemToToken.removeAll()
    }

    @discardableResult
    public func enqueue(url: URL) -> AnyHashable {
        let playerItem = AVPlayerItem(url: url)
        let token = AnyHashable(nextTokenID)
        nextTokenID += 1

        itemToToken[playerItem] = token

        // Insert after the last item so items play in enqueue order.
        player.insert(playerItem, after: player.items().last)
        return token
    }

    // MARK: - AudioPlayerBackend — State

    public var currentItemDuration: TimeInterval? {
        guard let duration = player.currentItem?.duration,
            duration.isNumeric,
            !duration.isIndefinite
        else {
            return nil
        }
        return duration.seconds
    }

    public var currentItemToken: AnyHashable? {
        guard let currentItem = player.currentItem else { return nil }
        return itemToToken[currentItem]
    }

    // MARK: - Private — Observer Setup

    /// Installs a periodic time observer that fires roughly every 0.5 seconds.
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.onTimeUpdate?(time.seconds)
            }
        }
    }

    /// Observes `player.rate` via KVO to detect external play/pause events
    /// (e.g. audio session interruption, stalling, AirPlay).
    private func setupRateObserver() {
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let newRate = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.onPlayingChanged?(newRate > 0)
            }
        }
    }

    /// Listens for item-end notifications and forwards them to `onItemDidFinish`.
    ///
    /// Two parallel tasks cover both termination paths:
    /// - `AVPlayerItemDidPlayToEndTime` — item played to its natural end.
    /// - `AVPlayerItemFailedToPlayToEndTime` — item failed to load or stream
    ///   (network error, auth expiry, server error, etc.).
    ///
    /// Both tasks run on the `@MainActor` (inherited from the `@MainActor`-isolated
    /// `init` that creates them), so all `itemToToken` and `onItemDidFinish` accesses
    /// are correctly actor-isolated.
    private func setupEndOfItemObserver() {
        endOfItemTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime
            ) {
                guard let self else { break }
                guard let finishedItem = notification.object as? AVPlayerItem,
                    let token = self.itemToToken[finishedItem]
                else { continue }
                self.itemToToken.removeValue(forKey: finishedItem)
                self.onItemDidFinish?(token)
            }
        }

        failedItemTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .AVPlayerItemFailedToPlayToEndTime
            ) {
                guard let self else { break }
                guard let finishedItem = notification.object as? AVPlayerItem,
                    let token = self.itemToToken[finishedItem]
                else { continue }
                self.itemToToken.removeValue(forKey: finishedItem)
                self.onItemDidFinish?(token)
            }
        }
    }
}
