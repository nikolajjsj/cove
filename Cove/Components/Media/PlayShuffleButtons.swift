import SwiftUI

/// Reusable Play + Shuffle button pair used by album and playlist detail views.
struct PlayShuffleButtons: View {
    let isDisabled: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDisabled)

            Button {
                onShuffle()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isDisabled)
        }
    }
}
