import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct PlaylistListView: View {
    @Environment(AppState.self) private var appState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading playlists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Playlists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("You haven't created any playlists yet.")
                )
            } else {
                List(playlists) { playlist in
                    PlaylistRow(
                        playlist: playlist,
                        imageURL: imageURL(for: playlist.id)
                    )
                }
                .listStyle(.plain)
            }
        }
        .task {
            await loadPlaylists()
        }
    }

    // MARK: - Data Loading

    private func loadPlaylists() async {
        isLoading = true
        errorMessage = nil
        do {
            playlists = try await appState.provider.playlists()
        } catch {
            errorMessage = error.localizedDescription
            playlists = []
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func imageURL(for itemId: ItemID, maxSize: CGSize? = CGSize(width: 120, height: 120))
        -> URL?
    {
        appState.provider.imageURL(for: itemId, type: .primary, maxSize: maxSize)
    }
}

// MARK: - Playlist Row

private struct PlaylistRow: View {
    let playlist: Playlist
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            MediaImage.artwork(url: imageURL, cornerRadius: 8)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let count = playlist.itemCount {
                        Text("\(count) \(count == 1 ? "track" : "tracks")")
                    }

                    if playlist.itemCount != nil, playlist.duration != nil {
                        Text("·")
                    }

                    if let duration = playlist.duration {
                        Text(TimeFormatting.longDuration(duration))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let overview = playlist.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

}

#Preview {
    NavigationStack {
        PlaylistListView()
            .environment(AppState())
    }
}
