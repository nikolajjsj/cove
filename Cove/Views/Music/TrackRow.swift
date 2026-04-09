import Models
import SwiftUI

/// A reusable row for displaying a music track with artwork, title, subtitle,
/// now-playing indicator, and duration.
///
/// Consolidates the previously duplicated `SongRow` (in `SongListView`) and
/// `PlaylistTrackRow` (in `PlaylistDetailView`) into a single source of truth.
///
/// ```swift
/// // From a MediaItem (song list):
/// TrackRow(
///     title: item.title,
///     subtitle: item.genres?.first,
///     imageURL: artworkURL,
///     duration: item.runtime,
///     isCurrentTrack: isCurrent,
///     isPlaying: isPlaying,
///     onTap: { playFromIndex(index) }
/// )
///
/// // From a Track model (playlist):
/// TrackRow(
///     title: track.title,
///     subtitle: track.artistName,
///     imageURL: artworkURL,
///     duration: track.duration,
///     isCurrentTrack: isCurrent,
///     isPlaying: isPlaying,
///     onTap: { playAllTracks(startingAt: index) }
/// )
/// ```
struct TrackRow: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let duration: TimeInterval?
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                MediaImage.trackThumbnail(url: imageURL)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(isCurrentTrack ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isCurrentTrack {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }

                if let duration, duration > 0 {
                    Text(TimeFormatting.trackTime(duration))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Track Row") {
        VStack(spacing: 0) {
            TrackRow(
                title: "Come Together",
                subtitle: "The Beatles",
                imageURL: nil,
                duration: 259,
                isCurrentTrack: false,
                isPlaying: false,
                onTap: {}
            )
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.leading, 68)

            TrackRow(
                title: "Here Comes The Sun",
                subtitle: "The Beatles",
                imageURL: nil,
                duration: 185,
                isCurrentTrack: true,
                isPlaying: true,
                onTap: {}
            )
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.leading, 68)

            TrackRow(
                title: "Let It Be",
                subtitle: "The Beatles",
                imageURL: nil,
                duration: 243,
                isCurrentTrack: false,
                isPlaying: false,
                onTap: {}
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
#endif
