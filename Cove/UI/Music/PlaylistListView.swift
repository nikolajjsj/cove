import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

struct PlaylistListView: View {
    var sortField: SortField = .name
    var sortOrder: Models.SortOrder = .ascending
    var isFavoriteFilter: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    private var sortedFilteredPlaylists: [Playlist] {
        var result = playlists
        if isFavoriteFilter {
            result = result.filter { $0.userData?.isFavorite == true }
        }
        switch sortField {
        case .name:
            result.sort {
                sortOrder == .ascending
                    ? $0.name.localizedCompare($1.name) == .orderedAscending
                    : $0.name.localizedCompare($1.name) == .orderedDescending
            }
        case .dateAdded:
            result.sort {
                let d0 = $0.dateAdded ?? .distantPast
                let d1 = $1.dateAdded ?? .distantPast
                return sortOrder == .ascending ? d0 < d1 : d0 > d1
            }
        default:
            break
        }
        return result
    }

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
            } else if sortedFilteredPlaylists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text(
                        isFavoriteFilter
                            ? "No favorite playlists found."
                            : "You haven't created any playlists yet.")
                )
            } else {
                List(sortedFilteredPlaylists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(
                            playlist: playlist,
                            imageURL: imageURL(for: playlist.id)
                        )
                    }
                    .playlistContextMenu(
                        playlist: playlist,
                        onRenamed: {
                            Task { await loadPlaylists() }
                        },
                        onDeleted: {
                            Task { await loadPlaylists() }
                        })
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await createPlaylist() }
            }
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for the new playlist.")
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
            playlists = try await authManager.provider.playlists()
        } catch {
            errorMessage = error.localizedDescription
            playlists = []
        }
        isLoading = false
    }

    private func createPlaylist() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let _ = try await authManager.provider.createPlaylist(name: name, trackIds: [])
            appState.showToast("Playlist created", icon: "checkmark.circle")
            await loadPlaylists()
        } catch {
            appState.showToast("Failed to create playlist", icon: "exclamationmark.triangle")
        }
    }

    // MARK: - Helpers

    private func imageURL(for itemId: ItemID, maxSize: CGSize? = CGSize(width: 120, height: 120))
        -> URL?
    {
        authManager.provider.imageURL(for: itemId, type: .primary, maxSize: maxSize)
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
    let state = AppState.preview
    NavigationStack {
        PlaylistListView()
            .environment(state)
            .environment(state.authManager)
    }
}
