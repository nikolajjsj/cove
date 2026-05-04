import Models
import PlaybackEngine
import SwiftUI

/// Lyrics page in the full-screen audio player.
///
/// Displays synchronized or unsynchronized lyrics for the current track.
/// Synchronized lyrics auto-scroll to keep the active line centred in the
/// viewport as the track plays. The user can scroll manually at any time;
/// auto-scroll resumes three seconds after the last interaction.
///
/// Lyrics are fetched through ``LyricsStore`` on `AppState`, which deduplicates
/// requests — if `CurrentLyricPreview` already loaded the lyrics while the artwork
/// page was visible, they appear instantly without a second network round-trip.
struct LyricsView: View {
    let track: Track

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    @State private var lyrics: Lyrics?
    @State private var isLoading = true

    // MARK: - Derived State

    private var isSynced: Bool {
        lyrics?.lines.contains { $0.startTime != nil } == true
    }

    /// The index of the lyric line whose `startTime` is the latest one that is
    /// less-than-or-equal to the current playback position.
    private var currentLineIndex: Int? {
        guard let lyrics, isSynced else { return nil }
        let time = appState.audioPlayer.currentTime
        var result: Int?
        for (index, line) in lyrics.lines.enumerated() {
            guard let start = line.startTime else { continue }
            if start <= time { result = index } else { break }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics, !lyrics.lines.isEmpty {
                if isSynced {
                    SyncedLyricsView(
                        lines: lyrics.lines,
                        currentLineIndex: currentLineIndex,
                        onSeek: { appState.audioPlayer.seek(to: $0) }
                    )
                } else {
                    UnsyncedLyricsView(lines: lyrics.lines)
                }
            } else {
                ContentUnavailableView("Lyrics Not Available", systemImage: "music.note")
            }
        }
        .task(id: track.id) {
            await loadLyrics()
        }
    }

    // MARK: - Data Loading

    private func loadLyrics() async {
        isLoading = true
        lyrics = await appState.lyricsStore.lyrics(for: track.id, using: authManager.provider)
        isLoading = false
    }
}

// MARK: - Synced Lyrics

/// Scrolling lyrics view that auto-advances to keep the active line centred,
/// while respecting manual user scrolls.
///
/// Uses the modern `ScrollPosition` API instead of `ScrollViewReader` / `ScrollViewProxy`.
/// Auto-scroll is driven by `onChange(of: currentLineIndex)` rather than a per-change
/// `task(id:)`, which avoids spawning a new `Task` on every playback tick.
private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let currentLineIndex: Int?
    let onSeek: (TimeInterval) -> Void

    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var scrollViewHeight: CGFloat = 400
    @State private var isUserScrolling = false
    @State private var scrollPauseTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Top spacer so the first line can scroll to the centre of the viewport.
                Color.clear
                    .frame(height: scrollViewHeight / 2)

                ForEach(lines.enumerated(), id: \.offset) { index, line in
                    let isActive = currentLineIndex == index

                    Button {
                        if let start = line.startTime { onSeek(start) }
                    } label: {
                        Text(line.text)
                            .font(.title3)
                            .bold(isActive)
                            .opacity(isActive ? 1.0 : 0.4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .animation(.easeInOut(duration: 0.3), value: isActive)
                    }
                    .buttonStyle(.plain)
                    .id(index)
                }

                // Bottom spacer mirrors the top so the last line can also centre.
                Color.clear
                    .frame(height: scrollViewHeight / 2)
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting { pauseAutoScroll() }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { newHeight in
            if newHeight > 0 { scrollViewHeight = newHeight }
        }
        .onChange(of: currentLineIndex) { _, newIndex in
            guard let index = newIndex, !isUserScrolling else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                scrollPosition.scrollTo(id: index, anchor: .center)
            }
        }
    }

    // MARK: - Auto-Scroll

    private func pauseAutoScroll() {
        isUserScrolling = true
        scrollPauseTask?.cancel()
        scrollPauseTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isUserScrolling = false
        }
    }
}

// MARK: - Unsynced Lyrics

private struct UnsyncedLyricsView: View {
    let lines: [LyricLine]

    var body: some View {
        ScrollView {
            Text(lines.map(\.text).joined(separator: "\n"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .lineSpacing(8)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Preview

#Preview {
    let state = AppState.preview
    LyricsView(
        track: Track(id: TrackID("preview"), title: "Test Track")
    )
    .environment(state)
    .environment(state.authManager)
}
