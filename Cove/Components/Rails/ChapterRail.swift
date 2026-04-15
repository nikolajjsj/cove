import Models
import SwiftUI

/// A horizontal scroll rail that displays chapter markers for a media item.
///
/// Each chapter shows a 16:9 thumbnail image (when available), the chapter
/// name, and a formatted timestamp. Tapping a chapter invokes the `onSelect`
/// callback with that chapter's start position.
///
/// ```swift
/// ChapterRail(
///     chapters: movie.chapters,
///     chapterImageURL: { chapter in
///         serverURL.appending(path: "Items/\(itemId)/Images/Chapter/\(chapter.id)")
///     },
///     onSelect: { chapter in
///         player.seek(to: chapter.startPosition)
///     }
/// )
/// ```
struct ChapterRail: View {

    // MARK: - Configuration

    /// The chapters to display. If empty, the view renders nothing.
    let chapters: [Chapter]

    /// Optional closure that returns a thumbnail URL for a given chapter.
    /// Return `nil` to show the default placeholder.
    var chapterImageURL: ((Chapter) -> URL?)? = nil

    /// Called when the user taps a chapter card.
    let onSelect: (Chapter) -> Void

    // MARK: - Body

    var body: some View {
        if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Chapters")
                    .font(.title3)
                    .bold()
                    .padding(.horizontal)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(chapters) { chapter in
                            ChapterCard(
                                chapter: chapter,
                                imageURL: chapterImageURL?(chapter),
                                onSelect: onSelect
                            )
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Chapter Card

/// An individual chapter card showing a thumbnail, name, and timestamp.
private struct ChapterCard: View {

    let chapter: Chapter
    let imageURL: URL?
    let onSelect: (Chapter) -> Void

    var body: some View {
        Button {
            onSelect(chapter)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MediaImage.videoThumbnail(url: imageURL, cornerRadius: 8)
                    .frame(width: 200)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(TimeFormatting.playbackPosition(chapter.startPosition))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200)
        }
        .buttonStyle(.plain)
    }
}
