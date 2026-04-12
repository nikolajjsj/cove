import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// Page 2 of the paged player — displays synced or unsynced lyrics.
struct LyricsView: View {
    let track: Track
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var lyrics: Lyrics?
    @State private var isLoading = true
    @State private var isUserScrolling = false
    @State private var scrollPauseTask: Task<Void, Never>?
    @State private var scrollPosition = ScrollPosition()

    /// Whether the lyrics have sync timing data.
    private var isSynced: Bool {
        guard let lyrics else { return false }
        return lyrics.lines.contains { $0.startTime != nil }
    }

    /// Index of the currently active lyric line based on playback position.
    private var currentLineIndex: Int? {
        guard let lyrics, isSynced else { return nil }
        let time = appState.audioPlayer.currentTime
        var lastIndex: Int?
        for (index, line) in lyrics.lines.enumerated() {
            guard let startTime = line.startTime else { continue }
            if startTime <= time {
                lastIndex = index
            } else {
                break
            }
        }
        return lastIndex
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics, !lyrics.lines.isEmpty {
                if isSynced {
                    syncedLyricsView(lyrics: lyrics)
                } else {
                    unsyncedLyricsView(lyrics: lyrics)
                }
            } else {
                emptyState
            }
        }
        .task(id: track.id) {
            await loadLyrics()
        }
    }

    // MARK: - Synced Lyrics

    private func syncedLyricsView(lyrics: Lyrics) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Top spacer for centering
                Spacer()
                    .frame(height: 80)

                ForEach(lyrics.lines.enumerated(), id: \.offset) { index, line in
                    let isCurrentLine = currentLineIndex == index

                    Button {
                        if let startTime = line.startTime {
                            appState.audioPlayer.seek(to: startTime)
                        }
                    } label: {
                        Text(line.text)
                            .font(.title3.weight(isCurrentLine ? .bold : .regular))
                            .opacity(isCurrentLine ? 1.0 : 0.4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .animation(.easeInOut(duration: 0.3), value: isCurrentLine)
                    }
                    .buttonStyle(.plain)
                    .id(index)
                }

                // Bottom spacer
                Spacer()
                    .frame(height: 80)
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting {
                pauseAutoScroll()
            }
        }
        .onChange(of: currentLineIndex) { _, newIndex in
            guard let newIndex, !isUserScrolling else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                scrollPosition.scrollTo(id: newIndex, anchor: .center)
            }
        }
    }

    // MARK: - Unsynced Lyrics

    private func unsyncedLyricsView(lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 24)

                Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .lineSpacing(8)

                Spacer()
                    .frame(height: 24)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView("Lyrics Not Available", systemImage: "music.note")
    }

    // MARK: - Auto-Scroll Pause

    private func pauseAutoScroll() {
        isUserScrolling = true
        scrollPauseTask?.cancel()
        scrollPauseTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isUserScrolling = false
        }
    }

    // MARK: - Data Loading

    private func loadLyrics() async {
        isLoading = true
        do {
            lyrics = try await authManager.provider.lyrics(track: track.id)
        } catch {
            lyrics = nil
        }
        isLoading = false
    }
}

#Preview {
    let state = AppState.preview
    LyricsView(
        track: Track(id: TrackID("preview"), title: "Test Track")
    )
    .environment(state)
    .environment(state.authManager)
}
