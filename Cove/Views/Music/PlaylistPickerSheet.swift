import JellyfinProvider
import MediaServerKit
import Models
import SwiftUI

/// A sheet that lets the user add tracks to an existing playlist or create a new one.
///
/// Present as a sheet. On selection it adds the tracks, dismisses itself, and shows a toast.
///
/// Usage:
/// ```
/// .sheet(isPresented: $showPlaylistPicker) {
///     PlaylistPickerSheet(trackIds: [track.id])
/// }
/// ```
struct PlaylistPickerSheet: View {
    let trackIds: [ItemID]
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var isAdding = false

    private var filteredPlaylists: [Playlist] {
        if searchText.isEmpty {
            return playlists
        }
        return playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading playlists…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Create a playlist to get started.")
                    )
                } else {
                    List {
                        // New Playlist button
                        Button {
                            newPlaylistName = ""
                            showNewPlaylistAlert = true
                        } label: {
                            Label("New Playlist", systemImage: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }

                        // Existing playlists
                        ForEach(filteredPlaylists) { playlist in
                            Button {
                                Task { await addToPlaylist(playlist) }
                            } label: {
                                HStack(spacing: 12) {
                                    MediaImage.trackThumbnail(
                                        url: imageURL(for: playlist.id),
                                        cornerRadius: 6
                                    )
                                    .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if let count = playlist.itemCount {
                                            Text("\(count) \(count == 1 ? "track" : "tracks")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .disabled(isAdding)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search playlists")
                }
            }
            .navigationTitle("Add to Playlist")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    Task { await createNewPlaylist() }
                }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter a name for your new playlist.")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadPlaylists()
        }
    }

    // MARK: - Actions

    private func loadPlaylists() async {
        isLoading = true
        do {
            playlists = try await authManager.provider.playlists()
        } catch {
            playlists = []
        }
        isLoading = false
    }

    private func addToPlaylist(_ playlist: Playlist) async {
        isAdding = true
        do {
            try await authManager.provider.addToPlaylist(
                playlist: playlist.id, trackIds: trackIds
            )
            dismiss()
            let trackWord = trackIds.count == 1 ? "track" : "tracks"
            ToastManager.shared.show(
                "Added \(trackIds.count) \(trackWord) to \(playlist.name)",
                icon: "checkmark.circle.fill"
            )
        } catch {
            // Stay on sheet so user can retry
            isAdding = false
        }
    }

    private func createNewPlaylist() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isAdding = true
        do {
            _ = try await authManager.provider.createPlaylist(
                name: name, trackIds: trackIds
            )
            dismiss()
            ToastManager.shared.show("Added to \(name)", icon: "checkmark.circle.fill")
        } catch {
            isAdding = false
        }
    }

    // MARK: - Helpers

    private func imageURL(for itemId: ItemID) -> URL? {
        authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 88, height: 88))
    }
}

#Preview {
    let state = AppState.preview
    PlaylistPickerSheet(trackIds: [])
        .environment(state.authManager)
}
