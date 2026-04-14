import Models
import SwiftUI
import JellyfinProvider

/// A list row for displaying media items with watched state, progress, and context menus.
///
/// Provides feature parity with ``MediaCard`` in portrait mode, adapted to a
/// horizontal row layout suitable for `List` views. Shows a poster thumbnail,
/// title, subtitle metadata, and an optional watched/progress indicator.
///
/// ```swift
/// // In a List or ForEach:
/// MediaListRow(item: movie)
///
/// // In a grid toggle context:
/// ForEach(items) { item in
///     MediaListRow(item: item)
/// }
/// ```
struct MediaListRow: View {

    // MARK: - Input

    let item: MediaItem

    // MARK: - Environment

    @Environment(AuthManager.self) private var authManager
    @Environment(UserDataStore.self) private var userDataStore

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            MediaImage.poster(
                url: imageURL,
                aspectRatio: posterAspectRatio,
                icon: item.mediaType.placeholderIcon,
                cornerRadius: 6
            )
            .frame(width: 56, height: thumbnailHeight)
            .clipped()

            // Title and subtitle
            MediaListRowInfo(item: item)

            Spacer(minLength: 0)

            // Trailing watched/progress indicator
            MediaListRowTrailing(isPlayed: isPlayed, watchProgress: watchProgress)
        }
        .contentShape(.rect)
        .mediaContextMenu(item: item)
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

    /// Playback progress for video items that are meaningfully in-progress
    /// (between 1% and 99%) and not yet marked as fully played.
    private var watchProgress: Double? {
        guard item.mediaType.isVideo, !isPlayed else { return nil }
        let position = effectiveUserData.playbackPosition
        guard position > 0, let runtime = item.runtime, runtime > 0 else { return nil }
        let progress = position / runtime
        guard progress > 0.01 && progress < 0.99 else { return nil }
        return progress
    }

    /// Poster aspect ratio: square for music, portrait for video content.
    private var posterAspectRatio: Double {
        item.mediaType.isMusic ? 1.0 : 2.0 / 3.0
    }

    /// Thumbnail height derived from aspect ratio and a fixed 56pt width.
    private var thumbnailHeight: CGFloat {
        item.mediaType.isMusic ? 56 : 84
    }

    /// Image URL sized appropriately for the thumbnail.
    private var imageURL: URL? {
        let maxSize =
            item.mediaType.isMusic
            ? CGSize(width: 120, height: 120)
            : CGSize(width: 120, height: 180)
        return authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: maxSize
        )
    }
}

// MARK: - Row Info

/// Title and subtitle text content for a ``MediaListRow``.
struct MediaListRowInfo: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Subtitle Builder

    private var subtitleText: String? {
        switch item.mediaType {
        case .movie:
            return movieSubtitle
        case .series:
            return seriesSubtitle
        case .episode:
            return episodeSubtitle
        case .album, .artist, .track:
            return musicSubtitle
        default:
            return genericSubtitle
        }
    }

    /// "2023 · PG-13 · 2h 28m"
    private var movieSubtitle: String? {
        var parts: [String] = []
        if let year = item.productionYear {
            parts.append(String(year))
        }
        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }
        if let runtime = item.runtime, runtime > 0 {
            parts.append(TimeFormatting.duration(runtime))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "2008 · TV-MA"
    private var seriesSubtitle: String? {
        var parts: [String] = []
        if let year = item.productionYear {
            parts.append(String(year))
        }
        if let rating = item.officialRating, !rating.isEmpty {
            parts.append(rating)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "S3 E9 · Game of Thrones"
    private var episodeSubtitle: String? {
        var parts: [String] = []
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            parts.append("S\(season) E\(episode)")
        }
        if let series = item.seriesName, !series.isEmpty {
            parts.append(series)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Artist name or album name for music items.
    private var musicSubtitle: String? {
        if let artist = item.artistName, !artist.isEmpty {
            return artist
        }
        if let album = item.albumName, !album.isEmpty {
            return album
        }
        return nil
    }

    /// Year as a fallback for other media types.
    private var genericSubtitle: String? {
        if let year = item.productionYear {
            return String(year)
        }
        return nil
    }
}

// MARK: - Trailing Indicator

/// Watched badge or progress indicator displayed at the trailing edge of a ``MediaListRow``.
struct MediaListRowTrailing: View {
    let isPlayed: Bool
    let watchProgress: Double?

    var body: some View {
        if isPlayed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.body)
        } else if let progress = watchProgress {
            MediaListRowProgressRing(progress: progress)
        }
    }
}

// MARK: - Progress Ring

/// A small circular progress ring indicating partial watch progress.
struct MediaListRowProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2.5)
                .foregroundStyle(.quaternary)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(.accent)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Previews

#if DEBUG
    private let _previewState = AppState.preview
    private let _previewStore = UserDataStore(provider: _previewState.authManager.provider)

    #Preview("Movie — Unwatched") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("1"),
                    title: "Oppenheimer",
                    mediaType: .movie,
                    productionYear: 2023,
                    runTimeTicks: 108_000_000_000,
                    officialRating: "R"
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Movie — Watched") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("2"),
                    title: "Interstellar",
                    mediaType: .movie,
                    productionYear: 2014,
                    runTimeTicks: 100_200_000_000,
                    officialRating: "PG-13",
                    userData: UserData(isPlayed: true)
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Movie — In Progress") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("3"),
                    title: "Dune: Part Two",
                    mediaType: .movie,
                    productionYear: 2024,
                    runTimeTicks: 99_600_000_000,
                    officialRating: "PG-13",
                    userData: UserData(playbackPosition: 4_500)
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Episode") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("4"),
                    title: "The Rains of Castamere",
                    mediaType: .episode,
                    runTimeTicks: 34_200_000_000,
                    seriesName: "Game of Thrones",
                    indexNumber: 9,
                    parentIndexNumber: 3
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Series") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("5"),
                    title: "Breaking Bad",
                    mediaType: .series,
                    productionYear: 2008,
                    officialRating: "TV-MA"
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Music — Album") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("6"),
                    title: "Abbey Road",
                    mediaType: .album,
                    artistName: "The Beatles"
                )
            )

            MediaListRow(
                item: MediaItem(
                    id: ItemID("7"),
                    title: "OK Computer",
                    mediaType: .album,
                    artistName: "Radiohead"
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }

    #Preview("Mixed List") {
        List {
            MediaListRow(
                item: MediaItem(
                    id: ItemID("m1"),
                    title: "Oppenheimer",
                    mediaType: .movie,
                    productionYear: 2023,
                    runTimeTicks: 108_000_000_000,
                    officialRating: "R"
                )
            )

            MediaListRow(
                item: MediaItem(
                    id: ItemID("m2"),
                    title: "Interstellar",
                    mediaType: .movie,
                    productionYear: 2014,
                    officialRating: "PG-13",
                    userData: UserData(isPlayed: true)
                )
            )

            MediaListRow(
                item: MediaItem(
                    id: ItemID("m3"),
                    title: "Dune: Part Two",
                    mediaType: .movie,
                    productionYear: 2024,
                    runTimeTicks: 99_600_000_000,
                    officialRating: "PG-13",
                    userData: UserData(playbackPosition: 4_500)
                )
            )

            MediaListRow(
                item: MediaItem(
                    id: ItemID("e1"),
                    title: "The Rains of Castamere",
                    mediaType: .episode,
                    runTimeTicks: 34_200_000_000,
                    seriesName: "Game of Thrones",
                    indexNumber: 9,
                    parentIndexNumber: 3
                )
            )

            MediaListRow(
                item: MediaItem(
                    id: ItemID("a1"),
                    title: "Abbey Road",
                    mediaType: .album,
                    artistName: "The Beatles"
                )
            )
        }
        .environment(_previewState.authManager)
        .environment(_previewStore)
    }
#endif
