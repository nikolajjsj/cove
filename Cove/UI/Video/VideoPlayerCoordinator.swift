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

    /// Playback start position in seconds.
    private(set) var startPosition: TimeInterval = 0

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
                let info = try await provider.streamURL(for: item, profile: nil)
                currentItem = item
                streamInfo = info
                startPosition = item.userData?.playbackPosition ?? 0
                isPresented = true
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
                let info = try await provider.streamURL(for: episodeItem, profile: nil)
                currentItem = episodeItem
                streamInfo = info
                startPosition = episodeItem.userData?.playbackPosition ?? 0
                isPresented = true
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
            isTranscoded: false,
            directPlaySupported: true
        )
        currentItem = item
        streamInfo = info
        startPosition = item.userData?.playbackPosition ?? 0
        isPresented = true
    }

    /// Dismiss the video player and clear playback state.
    func dismiss() {
        isPresented = false
        // Delay clearing data so the fade-out animation can still reference the current item
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            currentItem = nil
            streamInfo = nil
            startPosition = 0
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

        var localizedDescription: String {
            underlyingError.localizedDescription
        }
    }
}
