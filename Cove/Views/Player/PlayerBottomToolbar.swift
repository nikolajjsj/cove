import Models
import PlaybackEngine
import SwiftUI

/// Bottom navigation toolbar for the full-screen audio player.
///
/// Tapping a toggle button activates that view; tapping the same button again
/// returns to the default artwork view.
struct PlayerBottomToolbar: View {
    @Binding var currentPage: PlayerPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            toggleButton(label: "Lyrics", icon: "quote.bubble", activePage: .lyrics)
            Spacer()
            toggleButton(label: "Queue", icon: "list.bullet", activePage: .queue)
            Spacer()
            SleepTimerButton()
            Spacer()
            Button("Dismiss player", systemImage: "chevron.down") {
                dismiss()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    private func toggleButton(label: String, icon: String, activePage: PlayerPage) -> some View {
        let isActive = currentPage == activePage

        return Button(label, systemImage: icon) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                currentPage = isActive ? .artwork : activePage
            }
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .buttonStyle(.plain)
    }
}

// MARK: - Sleep Timer Button (Isolated)

/// Isolated view that reads `player.sleepTimerMode` and
/// `player.sleepTimerRemaining` so the per-second countdown
/// doesn't invalidate the parent.
private struct SleepTimerButton: View {
    @Environment(AppState.self) private var appState

    private var player: AudioPlaybackManager { appState.audioPlayer }

    var body: some View {
        Menu {
            if player.sleepTimerMode != nil {
                Button(role: .destructive) {
                    player.cancelSleepTimer()
                    ToastManager.shared.show("Sleep timer cancelled", icon: "moon.zzz")
                } label: {
                    Label("Cancel Timer", systemImage: "xmark.circle")
                }

                Divider()
            }

            Button("5 minutes") { player.setSleepTimer(.minutes(5)) }
            Button("10 minutes") { player.setSleepTimer(.minutes(10)) }
            Button("15 minutes") { player.setSleepTimer(.minutes(15)) }
            Button("30 minutes") { player.setSleepTimer(.minutes(30)) }
            Button("45 minutes") { player.setSleepTimer(.minutes(45)) }
            Button("1 hour") { player.setSleepTimer(.minutes(60)) }
            Divider()
            Button("End of Track") { player.setSleepTimer(.endOfTrack) }
        } label: {
            Group {
                if player.sleepTimerMode != nil {
                    Image(systemName: "moon.zzz.fill")
                } else {
                    Image(systemName: "moon.zzz")
                }
            }
            .font(.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

