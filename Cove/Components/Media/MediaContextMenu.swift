import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// A unified context menu for any media item type.
///
/// Automatically shows the appropriate actions based on `item.mediaType`:
/// - **Movie/Episode**: Play, Mark Watched, Navigate to Series, Favorite
/// - **Series**: Mark Watched, Favorite
/// - **Collection** and others: Favorite
///
/// Usage:
/// ```swift
/// LibraryItemCard(item: item)
///     .mediaContextMenu(item: item)
/// ```
struct MediaContextMenuModifier: ViewModifier {
    let item: MediaItem

    /// When non-nil, a "Mark Previous Episodes as Watched" button is shown in
    /// the episode context menu. The closure is called when the user taps it.
    let onMarkPreviousWatched: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    func body(content: Content) -> some View {
        content.contextMenu { menuContent }
    }

    // MARK: - Menu Dispatch

    @ViewBuilder
    private var menuContent: some View {
        switch item.mediaType {
        case .movie:
            movieMenu
        case .episode:
            episodeMenu
        case .series:
            seriesMenu
        default:
            defaultMenu
        }
    }

    // MARK: - Movie Menu

    @ViewBuilder
    private var movieMenu: some View {
        playVideoButton
        Divider()
        PlayedToggle(itemId: item.id, userData: item.userData)
        Divider()
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Episode Menu

    @ViewBuilder
    private var episodeMenu: some View {
        playVideoButton

        Divider()

        PlayedToggle(itemId: item.id, userData: item.userData)

        if let onMarkPreviousWatched {
            Button(action: onMarkPreviousWatched) {
                Label("Mark Previous as Watched", systemImage: "eye.circle")
            }
        }

        if let seriesId = item.seriesId {
            Button {
                let series = MediaItem(
                    id: seriesId,
                    title: item.seriesName ?? "",
                    mediaType: .series
                )
                appState.navigate(to: .tvShows, destination: series)
            } label: {
                Label("Go to Series", systemImage: "tv")
            }
        }

        Divider()

        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Series Menu

    @ViewBuilder
    private var seriesMenu: some View {
        PlayedToggle(itemId: item.id, userData: item.userData)
        Divider()
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Default Menu

    @ViewBuilder
    private var defaultMenu: some View {
        FavoriteToggle(itemId: item.id, userData: item.userData)
    }

    // MARK: - Shared Action Buttons

    /// Play or resume a video item (movie or episode).
    private var playVideoButton: some View {
        Button {
            coordinator.play(item: item, using: authManager.provider)
        } label: {
            let position =
                appState.userDataStore?.userData(for: item.id, fallback: item.userData)
                .playbackPosition ?? 0
            Label(
                position > 0 ? "Resume" : "Play",
                systemImage: "play.fill"
            )
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Attaches a context menu appropriate for the given media item's type.
    ///
    /// Movies and episodes get playback actions, series get watched state, and
    /// everything gets a favorite toggle.
    func mediaContextMenu(item: MediaItem) -> some View {
        modifier(MediaContextMenuModifier(item: item, onMarkPreviousWatched: nil))
    }

    /// Attaches a context menu for an `Episode`, using the provided series
    /// context for "Go to Series" navigation.
    func mediaContextMenu(
        episode: Episode,
        seriesId: ItemID? = nil,
        seriesName: String? = nil,
        onMarkPreviousWatched: (() -> Void)? = nil
    ) -> some View {
        let item = MediaItem(
            id: ItemID(episode.id.rawValue),
            title: episode.title,
            overview: episode.overview,
            mediaType: .episode,
            runTimeTicks: episode.runtime.map { Int64($0 * 10_000_000) },
            userData: episode.userData,
            seriesName: seriesName,
            seriesId: seriesId,
            indexNumber: episode.episodeNumber,
            parentIndexNumber: episode.seasonNumber
        )
        return modifier(
            MediaContextMenuModifier(item: item, onMarkPreviousWatched: onMarkPreviousWatched))
    }
}
