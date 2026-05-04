import Foundation
import MediaPlayer
import Models

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Manages `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` for lock screen
/// and Control Center integration.
///
/// Registered command targets are tracked per-command so that ``teardown()`` can
/// remove exactly the targets this service added, without disturbing any targets
/// registered by other components (e.g. a future video player or a third-party SDK).
@MainActor
final class NowPlayingService: NowPlayingProvider {

    private var commandCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
    private var infoCenter: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }

    // MARK: - Remote Command Callbacks

    var onPlay: (@MainActor () -> Void)?
    var onPause: (@MainActor () -> Void)?
    var onNext: (@MainActor () -> Void)?
    var onPrevious: (@MainActor () -> Void)?
    var onSeek: (@MainActor (TimeInterval) -> Void)?
    var onTogglePlayPause: (@MainActor () -> Void)?
    var onToggleFavorite: (@MainActor () -> Void)?

    // MARK: - Private State

    /// Stores each registered (command, target) pair so ``teardown()`` can
    /// remove exactly our targets — not every target on the shared command center.
    private var registeredTargets: [(command: MPRemoteCommand, target: Any)] = []

    /// Tracks the track ID of the most-recently-requested artwork download,
    /// allowing stale responses to be silently discarded when the track changes.
    private var currentArtworkTrackID: TrackID?

    // MARK: - Setup & Teardown

    /// Register remote-command targets for playback control.
    ///
    /// Calls ``teardown()`` first to ensure a clean slate if called more than once.
    func setup() {
        teardown()

        let center = commandCenter

        register(center.playCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPlay?() }
            return .success
        }

        register(center.pauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPause?() }
            return .success
        }

        register(center.togglePlayPauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPause?() }
            return .success
        }

        register(center.nextTrackCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNext?() }
            return .success
        }

        register(center.previousTrackCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPrevious?() }
            return .success
        }

        register(center.changePlaybackPositionCommand) { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = positionEvent.positionTime
            Task { @MainActor [weak self] in self?.onSeek?(position) }
            return .success
        }

        center.likeCommand.isEnabled = true
        register(center.likeCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onToggleFavorite?() }
            return .success
        }
    }

    /// Remove all command targets registered by this service and clear now-playing info.
    func teardown() {
        for (command, target) in registeredTargets {
            command.removeTarget(target)
        }
        registeredTargets.removeAll()

        commandCenter.likeCommand.isEnabled = false
        commandCenter.likeCommand.isActive = false

        infoCenter.nowPlayingInfo = nil
        currentArtworkTrackID = nil
    }

    // MARK: - Now Playing Info

    /// Update the full now-playing metadata for a new track.
    func updateNowPlaying(
        track: Track,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        artworkURL: URL?
    ) {
        currentArtworkTrackID = track.id

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let artistName = track.artistName {
            info[MPMediaItemPropertyArtist] = artistName
        }
        if let albumName = track.albumName {
            info[MPMediaItemPropertyAlbumTitle] = albumName
        }
        if let trackNumber = track.trackNumber {
            info[MPMediaItemPropertyAlbumTrackNumber] = trackNumber
        }
        if let discNumber = track.discNumber {
            info[MPMediaItemPropertyDiscNumber] = discNumber
        }

        infoCenter.nowPlayingInfo = info

        if let artworkURL {
            loadArtwork(from: artworkURL, forTrackID: track.id)
        }
    }

    /// Update the active state of the favourite (heart) button on the lock screen.
    func updateFavoriteState(isFavorite: Bool) {
        commandCenter.likeCommand.isActive = isFavorite
    }

    /// Update only the playback-state fields of the existing now-playing info
    /// (elapsed time, playback rate, duration). Lightweight — called on a timer.
    func updatePlaybackState(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Private Helpers

    /// Register a handler on `command`, enable it, and record the (command, target) pair
    /// for later clean removal in ``teardown()``.
    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        registeredTargets.append((command, target))
    }

    /// Download artwork from `url` and inject it into the now-playing info.
    ///
    /// Uses `currentArtworkTrackID` to silently discard stale results when the
    /// track changes before the download completes.
    private func loadArtwork(from url: URL, forTrackID trackID: TrackID) {
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

            // Discard if the track changed while we were downloading.
            guard let self, self.currentArtworkTrackID == trackID else { return }

            #if os(iOS)
                guard let image = UIImage(data: data) else { return }
            #elseif os(macOS)
                guard let image = NSImage(data: data) else { return }
            #endif

            let artwork = MPMediaItemArtwork(image: image)

            guard var info = self.infoCenter.nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = artwork
            self.infoCenter.nowPlayingInfo = info
        }
    }
}
