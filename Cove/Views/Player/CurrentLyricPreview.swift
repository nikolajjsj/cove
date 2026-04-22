import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

/// Shows the currently active lyric line on the artwork page.
///
/// Isolated in its own struct so that per-tick `currentTime` observation only
/// re-renders this small subtree — not the parent controls view.
struct CurrentLyricPreview: View {
    let track: Track
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    /// Sorted synced-lyric entries loaded for the current track.
    @State private var syncedLines: [(startTime: TimeInterval, text: String)] = []

    /// The lyric line whose `startTime` is the latest one ≤ the current position.
    private var currentLineText: String? {
        guard !syncedLines.isEmpty else { return nil }
        let time = appState.audioPlayer.currentTime
        var result: String?
        for entry in syncedLines {
            if entry.startTime <= time {
                result = entry.text
            } else {
                break
            }
        }
        return result
    }

    var body: some View {
        Group {
            if let text = currentLineText, !text.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "music.microphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(text)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .id(text)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentLineText)
        .task(id: track.id) {
            await loadSyncedLines()
        }
    }

    private func loadSyncedLines() async {
        do {
            let lyrics = try await authManager.provider.lyrics(track: track.id)
            guard let lyrics else { return }
            syncedLines = lyrics.lines
                .compactMap { line in
                    guard let t = line.startTime else { return nil }
                    return (startTime: t, text: line.text)
                }
                .sorted { $0.startTime < $1.startTime }
        } catch {
            syncedLines = []
        }
    }
}
