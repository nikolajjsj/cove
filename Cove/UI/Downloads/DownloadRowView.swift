import DownloadManager
import Models
import SwiftUI

// MARK: - DownloadAction

/// Actions that can be performed on a download item from the UI.
enum DownloadAction: Sendable {
    case pause
    case resume
    case retry
    case delete
    case play
}

// MARK: - DownloadRowView

/// A single row in the downloads list showing item metadata, download state,
/// progress, and contextual actions via swipe gestures and context menus.
struct DownloadRowView: View {
    let item: DownloadItem
    let onAction: (DownloadAction, DownloadItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            mediaTypeIcon
                .frame(width: 36, height: 36)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)

                subtitleText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            stateIndicator
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.state == .completed {
                onAction(.play, item)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onAction(.delete, item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            switch item.state {
            case .downloading:
                if item.isResumable {
                    Button {
                        onAction(.pause, item)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .tint(.orange)
                } else {
                    Button(role: .destructive) {
                        onAction(.delete, item)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }

            case .paused, .queued:
                Button {
                    onAction(.resume, item)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.blue)

            case .failed:
                Button {
                    onAction(.retry, item)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(.blue)

            case .completed:
                EmptyView()
            }
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Media Type Icon

    private var mediaTypeIcon: some View {
        Image(systemName: iconName(for: item.mediaType))
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
    }

    private func iconName(for type: MediaType) -> String {
        switch type {
        case .movie: "film"
        case .episode: "tv"
        case .track: "music.note"
        case .album: "square.stack"
        case .series: "tv.and.mediabox"
        case .season: "list.and.film"
        case .artist: "music.mic"
        case .playlist: "music.note.list"
        case .book: "book"
        case .podcast: "antenna.radiowaves.left.and.right"
        case .collection: "rectangle.stack.fill"
        case .genre: "guitars"
        }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleText: some View {
        switch item.state {
        case .queued:
            Text("Waiting…")

        case .downloading:
            HStack(spacing: 4) {
                Text("\(Int(item.progress * 100))%")
                    .monospacedDigit()
                if item.totalBytes > 0 {
                    Text("·")
                    Text(item.formattedProgress)
                }
            }

        case .paused:
            HStack(spacing: 4) {
                Text("Paused")
                if item.progress > 0 {
                    Text("· \(Int(item.progress * 100))%")
                        .monospacedDigit()
                }
            }

        case .completed:
            HStack(spacing: 4) {
                Text(mediaTypeLabel(for: item.mediaType))
                if item.totalBytes > 0 {
                    Text("·")
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: item.totalBytes, countStyle: .file))
                }
            }

        case .failed:
            Text(item.errorMessage ?? "Download failed")
                .foregroundStyle(.red)
        }
    }

    private func mediaTypeLabel(for type: MediaType) -> String {
        switch type {
        case .movie: "Movie"
        case .episode: "Episode"
        case .track: "Track"
        case .album: "Album"
        case .series: "Series"
        case .season: "Season"
        case .artist: "Artist"
        case .playlist: "Playlist"
        case .book: "Book"
        case .podcast: "Podcast"
        case .collection: "Collection"
        case .genre: "Genre"
        }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch item.state {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.title3)

        case .downloading:
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: item.progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: item.isResumable ? "pause.fill" : "stop.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        switch item.state {
        case .downloading:
            if item.isResumable {
                Button {
                    onAction(.pause, item)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            } else {
                Button(role: .destructive) {
                    onAction(.delete, item)
                } label: {
                    Label("Stop Download", systemImage: "stop.fill")
                }
            }

        case .paused:
            Button {
                onAction(.resume, item)
            } label: {
                Label("Resume", systemImage: "play.fill")
            }

        case .queued:
            Button {
                onAction(.resume, item)
            } label: {
                Label("Start Now", systemImage: "play.fill")
            }

        case .completed:
            Button {
                onAction(.play, item)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

        case .failed:
            Button {
                onAction(.retry, item)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }

        Divider()

        Button(role: .destructive) {
            onAction(.delete, item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Preview

#Preview("Downloading") {
    List {
        DownloadRowView(
            item: DownloadItem(
                id: "1",
                itemId: ItemID("item-1"),
                serverId: "server-1",
                title: "Big Buck Bunny",
                mediaType: .movie,
                state: .downloading,
                progress: 0.65,
                totalBytes: 1_500_000_000,
                downloadedBytes: 975_000_000,
                localFilePath: nil,
                remoteURL: "https://example.com/movie.mp4",
                parentId: nil,
                artworkURL: nil,
                errorMessage: nil,
                createdAt: Date(),
                completedAt: nil
            ),
            onAction: { _, _ in }
        )

        DownloadRowView(
            item: DownloadItem(
                id: "2",
                itemId: ItemID("item-2"),
                serverId: "server-1",
                title: "Yesterday",
                mediaType: .track,
                state: .completed,
                progress: 1.0,
                totalBytes: 8_500_000,
                downloadedBytes: 8_500_000,
                localFilePath: "server-1/track/item-2/media.m4a",
                remoteURL: "https://example.com/track.m4a",
                parentId: ItemID("album-1"),
                artworkURL: nil,
                errorMessage: nil,
                createdAt: Date(),
                completedAt: Date()
            ),
            onAction: { _, _ in }
        )

        DownloadRowView(
            item: DownloadItem(
                id: "3",
                itemId: ItemID("item-3"),
                serverId: "server-1",
                title: "Episode 5 - The One Where They Download",
                mediaType: .episode,
                state: .failed,
                progress: 0.12,
                totalBytes: 500_000_000,
                downloadedBytes: 60_000_000,
                localFilePath: nil,
                remoteURL: "https://example.com/episode.mp4",
                parentId: ItemID("series-1"),
                artworkURL: nil,
                errorMessage: "Network connection lost",
                createdAt: Date(),
                completedAt: nil
            ),
            onAction: { _, _ in }
        )
    }
}
