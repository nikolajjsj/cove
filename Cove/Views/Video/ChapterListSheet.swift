import JellyfinProvider
import Models
import SwiftUI

/// A sheet presenting the list of chapters for the current video.
///
/// Shows chapter names with timestamps and highlights the currently playing chapter.
/// Tapping a chapter seeks to that position.
struct ChapterListSheet: View {
    let chapters: [Chapter]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let itemId: ItemID
    let onSelectChapter: (Chapter) -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    onSelectChapter(chapter)
                } label: {
                    ChapterRow(
                        chapter: chapter,
                        chapters: chapters,
                        currentTime: currentTime,
                        itemId: itemId
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Chapters")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let chapter: Chapter
    let chapters: [Chapter]
    let currentTime: TimeInterval
    let itemId: ItemID

    var body: some View {
        HStack(spacing: 14) {
            ChapterThumbnailView(chapter: chapter, itemId: itemId)
                .frame(width: 100, height: 56)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(2)

                Text(TimeFormatting.playbackPosition(chapter.startPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    /// Determines if this chapter is the one currently playing.
    private var isCurrent: Bool {
        guard !chapters.isEmpty else { return false }

        // Find the last chapter whose start position is at or before current time
        let sortedChapters = chapters.sorted { $0.startPosition < $1.startPosition }
        guard let currentChapter = sortedChapters.last(where: { $0.startPosition <= currentTime })
        else {
            return chapter.id == sortedChapters.first?.id
        }
        return chapter.id == currentChapter.id
    }
}

// MARK: - Chapter Thumbnail

private struct ChapterThumbnailView: View {
    let chapter: Chapter
    let itemId: ItemID

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if let imageTag = chapter.imageTag {
            let url = authManager.provider.chapterImageURL(
                itemId: itemId,
                chapterIndex: chapter.id,
                tag: imageTag,
                maxWidth: 200
            )
            MediaImage.videoThumbnail(url: url, cornerRadius: 0)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
