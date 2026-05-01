import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI

/// A unified card for displaying media items across grids, rails, and lists.
///
/// `MediaCard` consolidates four previously separate card components —
/// `LibraryItemCard`, `LandscapeMediaCard`, `ContinueWatchingCard`, and
/// `UpNextCard` — into a single component that adapts its layout based on
/// the ``MediaCard/Style-swift.enum`` parameter.
///
/// **Portrait (default):** A poster card suited for library grids and rails.
/// Music items render with a square (1:1) aspect ratio; all other media use
/// 2:3. A ``WatchedBadge`` is shown for fully-played video items, and a
/// ``VideoProgressOverlay`` is shown for partially-watched ones.
///
/// **Landscape:** A 16:9 thumbnail card suited for horizontal rails showing
/// trailers, special features, up-next episodes, and continue-watching items.
/// Always renders a tappable play button. When the item has playback progress,
/// the button moves to the bottom-leading corner alongside a progress bar;
/// otherwise it is centred over a subtle scrim. The subtitle adapts
/// automatically — "42 min remaining" for in-progress items, or the full
/// runtime for unwatched ones.
///
/// ```swift
/// // Library grid — portrait poster with watched state and progress bar
/// MediaCard(item: movie)
///
/// // Trailer / special feature — landscape with centred play button
/// MediaCard(item: trailer, style: .landscape)
///
/// // Continue Watching / Up Next — landscape, auto-adapts to progress state
/// MediaCard(item: episode, style: .landscape)
/// ```
struct MediaCard: View {

    // MARK: - Style

    /// Controls the overall layout of the card.
    enum Style {
        /// Portrait (2:3) poster or square (1:1) music artwork.
        ///
        /// Suitable for library grids, recommendation rails, and any context
        /// where the primary artwork is a poster image.
        case portrait

        /// Widescreen (16:9) video thumbnail with a tappable play button.
        ///
        /// Suitable for trailers, special features, up-next episodes, and
        /// continue-watching items. Play-button position and subtitle text
        /// adapt automatically based on the item's playback progress.
        case landscape
    }

    // MARK: - Input

    let item: MediaItem
    var style: Style = .portrait

    // MARK: - Environment

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(UserDataStore.self) private var userDataStore

    // MARK: - Body

    var body: some View {
        switch style {
        case .portrait:
            MediaCardPortraitLayout(
                item: item,
                imageURL: portraitImageURL,
                isPlayed: isPlayed,
                watchProgress: portraitWatchProgress
            )
        case .landscape:
            MediaCardLandscapeLayout(
                item: item,
                imageURL: landscapeImageURL,
                watchProgress: landscapeWatchProgress,
                remainingMinutes: remainingMinutes,
                coordinator: appState.videoPlayerCoordinator,
                provider: authManager.provider
            )
        }
    }

    // MARK: - Derived Data

    /// Effective user data, incorporating any optimistic overrides from the store.
    private var effectiveUserData: UserData {
        userDataStore.userData(for: item.id, fallback: item.userData)
    }

    /// Whether the item has been fully watched.
    private var isPlayed: Bool {
        effectiveUserData.isPlayed
    }

    /// Full-resolution poster image URL used by portrait cards.
    private var portraitImageURL: URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 300, height: 450)
        )
    }

    /// Widescreen thumbnail URL used by landscape cards.
    ///
    /// Episodes use the primary (screenshot) image. Movies and everything else
    /// prefer the backdrop image, falling back to primary when unavailable.
    private var landscapeImageURL: URL? {
        switch item.mediaType {
        case .episode:
            return authManager.provider.imageURL(
                for: item,
                type: .primary,
                maxSize: CGSize(width: 480, height: 270)
            )
        default:
            return authManager.provider.imageURL(
                for: item,
                type: .backdrop,
                maxSize: CGSize(width: 480, height: 270)
            )
                ?? authManager.provider.imageURL(
                    for: item,
                    type: .primary,
                    maxSize: CGSize(width: 480, height: 270)
                )
        }
    }

    /// Playback progress for portrait cards.
    ///
    /// Only non-nil for video items that are meaningfully in-progress (between
    /// 1 % and 99 %) and not yet marked as fully played.
    private var portraitWatchProgress: Double? {
        guard item.mediaType.isVideo, !isPlayed else { return nil }
        let position = effectiveUserData.playbackPosition
        guard position > 0, let runtime = item.runtime, runtime > 0 else { return nil }
        let progress = position / runtime
        guard progress > 0.01 && progress < 0.99 else { return nil }
        return progress
    }

    /// Playback progress for landscape cards.
    ///
    /// Non-nil whenever there is a meaningful playback position, clamped to
    /// [0.01, 0.99] so the progress bar always shows some visible fill.
    private var landscapeWatchProgress: Double? {
        let position = effectiveUserData.playbackPosition
        guard position > 0, let runtime = item.runtime, runtime > 0 else { return nil }
        return min(max(position / runtime, 0.01), 0.99)
    }

    /// Pre-computed remaining playback time in whole minutes.
    ///
    /// Used by the landscape subtitle to show "42 min remaining". `nil` when
    /// the item has no in-progress position or no runtime information.
    private var remainingMinutes: Int? {
        guard landscapeWatchProgress != nil else { return nil }
        let position = effectiveUserData.playbackPosition
        guard let runtime = item.runtime, runtime > 0 else { return nil }
        let minutes = Int(max(runtime - position, 0)) / 60
        return minutes > 0 ? minutes : nil
    }
}

// MARK: - Portrait Layout

/// Full layout for a portrait-style ``MediaCard``.
private struct MediaCardPortraitLayout: View {
    let item: MediaItem
    let imageURL: URL?
    let isPlayed: Bool
    let watchProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaCardPosterView(
                item: item,
                imageURL: imageURL,
                isPlayed: isPlayed,
                watchProgress: watchProgress
            )

            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .mediaContextMenu(item: item)
    }
}

// MARK: - Poster Image View

/// Poster artwork with an optional ``WatchedBadge`` and ``VideoProgressOverlay``.
private struct MediaCardPosterView: View {
    let item: MediaItem
    let imageURL: URL?
    let isPlayed: Bool
    let watchProgress: Double?

    var body: some View {
        // Outer ZStack pins the watched badge to the top-trailing corner.
        ZStack(alignment: .topTrailing) {
            // Inner ZStack pins the progress bar to the bottom edge.
            ZStack(alignment: .bottom) {
                MediaImage.poster(
                    url: imageURL,
                    aspectRatio: item.mediaType.isMusic ? 1.0 : 2.0 / 3.0,
                    icon: item.mediaType.placeholderIcon,
                    cornerRadius: 8
                )

                if let progress = watchProgress {
                    VideoProgressOverlay(progress: progress)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }

            if isPlayed {
                WatchedBadge()
            }
        }
    }
}

// MARK: - Landscape Layout

/// Full layout for a landscape-style ``MediaCard``.
private struct MediaCardLandscapeLayout: View {
    let item: MediaItem
    let imageURL: URL?
    let watchProgress: Double?
    let remainingMinutes: Int?
    let coordinator: VideoPlayerCoordinator
    let provider: JellyfinServerProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                MediaImage.videoThumbnail(url: imageURL, cornerRadius: 8)

                // Subtle dark scrim when no in-progress content, so the
                // centred play button is legible against any thumbnail colour.
                if watchProgress == nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.15))
                }

                // Progress bar pinned to the bottom edge.
                if let progress = watchProgress {
                    VStack {
                        Spacer()
                        VideoProgressOverlay(progress: progress, trackHeight: 4)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }

                // Play button position adapts to the item's progress state:
                // - In-progress: small, bottom-leading, alongside the bar.
                // - Not started: large, centred over the scrim.
                if watchProgress != nil {
                    MediaCardPlayButton(
                        item: item,
                        coordinator: coordinator,
                        provider: provider
                    )
                    .font(.title)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                } else {
                    MediaCardPlayButton(
                        item: item,
                        coordinator: coordinator,
                        provider: provider
                    )
                    .font(.largeTitle)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                }
            }

            MediaCardLandscapeInfo(
                item: item,
                watchProgress: watchProgress,
                remainingMinutes: remainingMinutes
            )
        }
        .mediaContextMenu(item: item)
    }
}

// MARK: - Play Button

/// Tappable play button used inside a ``MediaCardLandscapeLayout``.
///
/// While the coordinator is resolving this item's stream the button overlays
/// a `ProgressView` and disables itself to prevent double-taps.
private struct MediaCardPlayButton: View {
    let item: MediaItem
    let coordinator: VideoPlayerCoordinator
    let provider: JellyfinServerProvider

    var body: some View {
        Button("Play", systemImage: "play.circle.fill") {
            coordinator.play(item: item, using: provider)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.white)
        .overlay {
            if coordinator.isLoadingItem(item.id) {
                ProgressView()
                    .tint(.white)
            }
        }
        .disabled(coordinator.isLoadingItem(item.id))
    }
}

// MARK: - Landscape Info

/// Title and adaptive subtitle for a landscape ``MediaCard``.
///
/// - In-progress items display "S2 E5 · Breaking Bad — 42 min remaining".
/// - Unwatched items display "S2 E5 · Breaking Bad — 1h 23m".
/// - Non-episode items display only the runtime (or nothing if unavailable).
private struct MediaCardLandscapeInfo: View {
    let item: MediaItem
    let watchProgress: Double?
    let remainingMinutes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Subtitle Builder

    private var subtitleText: String? {
        var parts: [String] = []

        // Episode identifier and series name.
        if item.mediaType == .episode {
            var episodePart = ""
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                episodePart = "S\(season) E\(episode)"
            }
            if let series = item.seriesName, !series.isEmpty {
                episodePart += episodePart.isEmpty ? series : " · \(series)"
            }
            if !episodePart.isEmpty {
                parts.append(episodePart)
            }
        }

        // Time: remaining for in-progress items, full runtime otherwise.
        if let minutes = remainingMinutes {
            parts.append("\(minutes) min remaining")
        } else if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

// MARK: - Previews

#if DEBUG
    private let _previewState = AppState.preview
    private let _previewStore = UserDataStore(provider: _previewState.authManager.provider)

    #Preview("Portrait — Unwatched") {
        MediaCard(
            item: MediaItem(
                id: ItemID("1"),
                title: "Oppenheimer",
                mediaType: .movie,
                productionYear: 2023
            )
        )
        .frame(width: 130)
        .padding()
        .environment(_previewState)
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Portrait — Watched") {
        MediaCard(
            item: MediaItem(
                id: ItemID("2"),
                title: "Interstellar",
                mediaType: .movie,
                userData: UserData(isPlayed: true)
            )
        )
        .frame(width: 130)
        .padding()
        .environment(_previewState)
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Portrait — In Progress") {
        MediaCard(
            item: MediaItem(
                id: ItemID("3"),
                title: "Dune: Part Two",
                mediaType: .movie,
                runTimeTicks: 9_000_000_000,
                userData: UserData(playbackPosition: 2_700)
            )
        )
        .frame(width: 130)
        .padding()
        .environment(_previewState)
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Landscape — Up Next") {
        MediaCard(
            item: MediaItem(
                id: ItemID("4"),
                title: "The Rains of Castamere",
                mediaType: .episode,
                runTimeTicks: 34_200_000_000,
                seriesName: "Game of Thrones",
                indexNumber: 9,
                parentIndexNumber: 3
            ),
            style: .landscape
        )
        .frame(width: 240)
        .padding()
        .environment(_previewState)
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Landscape — In Progress") {
        MediaCard(
            item: MediaItem(
                id: ItemID("5"),
                title: "Winter is Coming",
                mediaType: .episode,
                runTimeTicks: 34_200_000_000,
                userData: UserData(playbackPosition: 1_800),
                seriesName: "Game of Thrones",
                indexNumber: 1,
                parentIndexNumber: 1
            ),
            style: .landscape
        )
        .frame(width: 240)
        .padding()
        .environment(_previewState)
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }
#endif
