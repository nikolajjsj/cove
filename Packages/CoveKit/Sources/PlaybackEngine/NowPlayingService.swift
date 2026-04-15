import Foundation
import MediaPlayer
import Models

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter for lock screen / Control Center integration.
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

    /// Stored command targets for cleanup.
    private var commandTargets: [Any] = []

    /// Tracks the current artwork request to avoid stale updates.
    private var currentArtworkTrackID: TrackID?

    // MARK: - Setup & Teardown

    /// Register remote command targets for playback control.
    func setup() {
        teardown()

        let center = commandCenter

        center.playCommand.isEnabled = true
        commandTargets.append(
            center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onPlay?()
                }
                return .success
            }
        )

        center.pauseCommand.isEnabled = true
        commandTargets.append(
            center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onPause?()
                }
                return .success
            }
        )

        center.togglePlayPauseCommand.isEnabled = true
        commandTargets.append(
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onTogglePlayPause?()
                }
                return .success
            }
        )

        center.nextTrackCommand.isEnabled = true
        commandTargets.append(
            center.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onNext?()
                }
                return .success
            }
        )

        center.previousTrackCommand.isEnabled = true
        commandTargets.append(
            center.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onPrevious?()
                }
                return .success
            }
        )

        center.changePlaybackPositionCommand.isEnabled = true
        commandTargets.append(
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                let position = positionEvent.positionTime
                Task { @MainActor [weak self] in
                    self?.onSeek?(position)
                }
                return .success
            }
        )
    }

    /// Remove all remote command targets and clear now playing info.
    func teardown() {
        let center = commandCenter
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        commandTargets.removeAll()

        infoCenter.nowPlayingInfo = nil
        currentArtworkTrackID = nil
    }

    // MARK: - Now Playing Info

    /// Update the full now playing info for a new track.
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

        infoCenter.nowPlayingInfo = info

        // Load artwork asynchronously
        if let artworkURL {
            loadArtwork(from: artworkURL, forTrackID: track.id)
        }
    }

    /// Update only the playback state (elapsed time, rate, duration) in the existing now playing info.
    func updatePlaybackState(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Private

    /// Download artwork from a URL and set it in the now playing info.
    /// Checks `currentArtworkTrackID` to discard stale results if the track changed.
    private func loadArtwork(from url: URL, forTrackID trackID: TrackID) {
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

            // Discard if the track changed while we were downloading
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
