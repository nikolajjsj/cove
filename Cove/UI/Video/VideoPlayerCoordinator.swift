import Defaults
import Foundation
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// Centralized coordinator for video playback presentation.
///
/// Instead of each detail view (MovieDetailView, SeriesDetailView, etc.) independently
/// managing stream resolution, error alerts, and player presentation via their own
/// `@State` properties, this coordinator owns all of that state in one place.
///
/// The video player is presented as a fullscreen ZStack overlay in `RootView`,
/// covering everything (tab bars, navigation bars, sheets) with a cinematic
/// fade+scale transition. This avoids the modal sheet/fullScreenCover mechanics
/// that cause dismiss-gesture conflicts with player controls on iOS.
///
/// Any view in the hierarchy can trigger playback by calling `play(item:using:)`.
/// This matches how Netflix, Apple TV+, Disney+, etc. handle video playback:
/// — A single full-screen player presented from the root of the app.
/// — Detail views simply request "play this"; they don't own the player lifecycle.
@Observable
@MainActor
final class VideoPlayerCoordinator {

    // MARK: - Presentation State

    /// Whether the video player is currently presented.
    var isPresented: Bool = false

    /// The item being played (movie or episode).
    private(set) var currentItem: MediaItem?

    /// Resolved stream info for the current item.
    private(set) var streamInfo: StreamInfo?

    /// Skippable segments (intro, credits, recap, etc.) for the current item.
    private(set) var mediaSegments: [MediaSegment] = []

    /// Playback start position in seconds.
    private(set) var startPosition: TimeInterval = 0

    /// Whether the resume prompt is showing.
    var showResumePrompt: Bool = false

    /// The saved position for the resume prompt.
    private(set) var savedPosition: TimeInterval = 0

    // MARK: - Loading State

    /// Whether we're currently resolving a stream URL.
    private(set) var isLoading: Bool = false

    /// The ID of the item currently being resolved (useful for showing per-row spinners).
    private(set) var loadingItemId: ItemID?

    // MARK: - Error State

    /// Non-nil when stream resolution failed; drives an alert in the UI.
    var error: PlaybackError?

    /// Whether the error alert should be shown (computed binding helper).
    var showError: Bool {
        get { error != nil }
        set { if !newValue { error = nil } }
    }

    // MARK: - Quality

    /// The provider used for the current session — retained for mid-playback quality switching.
    private var activeProvider: JellyfinServerProvider?

    /// The source video resolution (height) of the current item, used to build the quality picker.
    private(set) var sourceVideoHeight: Int?

    /// The source video bitrate of the current item, used to label "Original" quality.
    private(set) var sourceVideoBitrate: Int?

    /// The currently active streaming quality for this session.
    private(set) var activeQuality: StreamingQuality = .auto

    /// Whether a quality switch is in progress.
    private(set) var isSwitchingQuality: Bool = false

    /// Build a device profile constrained to the given quality tier.
    private func profileForQuality(_ quality: StreamingQuality) -> DeviceProfile? {
        guard let bitrate = quality.maxBitrate else { return nil }
        return DeviceProfile.appleDevice(maxStreamingBitrate: bitrate)
    }

    /// Available quality options for the current item, based on source resolution.
    var availableQualities: [StreamingQuality] {
        guard let height = sourceVideoHeight else { return [.auto] }
        var options: [StreamingQuality] = [.auto]
        if height > 1080 { options.append(.quality1080p) }
        if height > 720 { options.append(.quality720p) }
        if height > 480 { options.append(.quality480p) }
        return options
    }

    /// Switch quality mid-playback. Re-resolves the stream with a new device profile.
    func switchQuality(
        to quality: StreamingQuality,
        currentTime: TimeInterval
    ) {
        guard let provider = activeProvider, let item = currentItem, !isSwitchingQuality else {
            return
        }

        isSwitchingQuality = true
        activeQuality = quality

        Task {
            defer { isSwitchingQuality = false }
            do {
                let profile = profileForQuality(quality)
                let info = try await provider.streamURL(for: item, profile: profile)
                streamInfo = info
                startPosition = currentTime
            } catch {
                // Quality switch failed — keep playing at the current quality
            }
        }
    }

    // MARK: - Play

    /// Resolve the stream for `item` and present the video player.
    ///
    /// - Parameters:
    ///   - item: The `MediaItem` to play (movie or episode).
    ///   - provider: The Jellyfin server provider used to resolve the stream URL.
    func play(item: MediaItem, using provider: JellyfinServerProvider) {
        guard !isLoading else { return }

        Task {
            isLoading = true
            loadingItemId = item.id
            defer {
                isLoading = false
                loadingItemId = nil
            }

            do {
                let quality = Defaults[.maxStreamingQuality]
                let profile = profileForQuality(quality)

                async let infoTask = provider.streamURL(for: item, profile: profile)
                async let segmentsTask = provider.mediaSegments(for: item.id)

                let info = try await infoTask
                let segments = try await segmentsTask

                // Extract source video resolution for the quality picker
                let videoStream = info.mediaStreams.first { $0.type == .video }
                sourceVideoHeight = videoStream?.height
                sourceVideoBitrate = videoStream?.bitrate
                activeQuality = quality
                activeProvider = provider

                currentItem = item
                streamInfo = info
                mediaSegments = segments

                let position = item.userData?.playbackPosition ?? 0
                if position > 30 {
                    // Meaningful progress — ask the user
                    savedPosition = position
                    showResumePrompt = true
                } else {
                    // No meaningful progress — start from the beginning
                    startPosition = 0
                    isPresented = true
                }
            } catch {
                self.error = PlaybackError(
                    itemTitle: item.title,
                    underlyingError: error
                )
            }
        }
    }

    /// Resolve the stream for an episode that may need to be fetched first.
    ///
    /// This is the flow for `SeriesDetailView` where we have an `Episode` model
    /// but need to fetch the full `MediaItem` before resolving the stream.
    ///
    /// - Parameters:
    ///   - episodeId: The ID of the episode to play.
    ///   - episodeTitle: Display title (used in error messages).
    ///   - provider: The Jellyfin server provider.
    func playEpisode(
        id episodeId: ItemID,
        title episodeTitle: String,
        using provider: JellyfinServerProvider
    ) {
        guard !isLoading else { return }

        Task {
            isLoading = true
            loadingItemId = episodeId
            defer {
                isLoading = false
                loadingItemId = nil
            }

            do {
                let episodeItem = try await provider.item(id: episodeId)

                let quality = Defaults[.maxStreamingQuality]
                let profile = profileForQuality(quality)

                async let infoTask = provider.streamURL(for: episodeItem, profile: profile)
                async let segmentsTask = provider.mediaSegments(for: episodeId)

                let info = try await infoTask
                let segments = try await segmentsTask

                // Extract source video resolution for the quality picker
                let videoStream = info.mediaStreams.first { $0.type == .video }
                sourceVideoHeight = videoStream?.height
                sourceVideoBitrate = videoStream?.bitrate
                activeQuality = quality
                activeProvider = provider

                currentItem = episodeItem
                streamInfo = info
                mediaSegments = segments

                let position = episodeItem.userData?.playbackPosition ?? 0
                if position > 30 {
                    savedPosition = position
                    showResumePrompt = true
                } else {
                    startPosition = 0
                    isPresented = true
                }
            } catch {
                self.error = PlaybackError(
                    itemTitle: episodeTitle,
                    underlyingError: error
                )
            }
        }
    }

    /// Play a video item directly from a local file URL (for offline downloads).
    ///
    /// This bypasses stream URL resolution entirely, using the local file
    /// as a direct-play source. Used for downloaded movies and episodes.
    func playLocal(item: MediaItem, localFileURL: URL) {
        let info = StreamInfo(
            url: localFileURL,
            playMethod: .directPlay
        )
        currentItem = item
        streamInfo = info
        mediaSegments = []
        sourceVideoHeight = nil
        sourceVideoBitrate = nil
        activeQuality = .auto
        activeProvider = nil
        startPosition = item.userData?.playbackPosition ?? 0
        isPresented = true
    }

    /// User chose "Resume" — start from the saved position.
    func resumePlayback() {
        startPosition = savedPosition
        showResumePrompt = false
        isPresented = true
    }

    /// User chose "Play from Beginning" — start from 0.
    func playFromBeginning() {
        startPosition = 0
        showResumePrompt = false
        isPresented = true
    }

    /// User dismissed the resume prompt without choosing.
    func cancelResume() {
        showResumePrompt = false
        currentItem = nil
        streamInfo = nil
        savedPosition = 0
    }

    /// Dismiss the video player and clear playback state.
    func dismiss() {
        isPresented = false
        showResumePrompt = false
        // Delay clearing data so the fade-out animation can still reference the current item
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            currentItem = nil
            streamInfo = nil
            mediaSegments = []
            sourceVideoHeight = nil
            sourceVideoBitrate = nil
            activeQuality = .auto
            activeProvider = nil
            startPosition = 0
            savedPosition = 0
        }
    }

    /// Transition to the next episode without dismissing the player.
    ///
    /// Reports playback stopped on the current item, resolves the stream
    /// for the next episode, and swaps the player content in place.
    func transitionToNextEpisode(
        _ nextItem: MediaItem,
        using provider: JellyfinServerProvider
    ) async {
        do {
            let quality = Defaults[.maxStreamingQuality]
            let profile = profileForQuality(quality)

            async let infoTask = provider.streamURL(for: nextItem, profile: profile)
            async let segmentsTask = provider.mediaSegments(for: nextItem.id)

            let info = try await infoTask
            let segments = try await segmentsTask

            // Update coordinator state for the new item
            let videoStream = info.mediaStreams.first { $0.type == .video }
            sourceVideoHeight = videoStream?.height
            sourceVideoBitrate = videoStream?.bitrate
            activeQuality = quality
            activeProvider = provider

            currentItem = nextItem
            streamInfo = info
            mediaSegments = segments
            startPosition = 0
        } catch {
            // If transition fails, surface the error and dismiss
            self.error = PlaybackError(
                itemTitle: nextItem.title,
                underlyingError: error
            )
            dismiss()
        }
    }

    /// Check if a specific item is currently being resolved.
    func isLoadingItem(_ id: ItemID) -> Bool {
        isLoading && loadingItemId == id
    }
}

// MARK: - Error Type

extension VideoPlayerCoordinator {

    /// A playback error with enough context to show a useful alert.
    struct PlaybackError: Identifiable {
        let id = UUID()
        let itemTitle: String
        let underlyingError: Error

        /// User-friendly message explaining what went wrong and what to try.
        var localizedDescription: String {
            let nsError = underlyingError as NSError

            // Stream resolution errors (from our code)
            if underlyingError is AppError {
                return underlyingError.localizedDescription
            }

            // AVFoundation / network errors — give the user something actionable
            let detail = nsError.localizedFailureReason ?? nsError.localizedDescription
            return
                "The server could not provide a playable stream. This may happen if the file requires transcoding and your server doesn't have enough resources.\n\n(\(detail))"
        }
    }
}
