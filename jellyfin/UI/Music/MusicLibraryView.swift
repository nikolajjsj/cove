import Models
import SwiftUI

struct MusicLibraryView: View {
    let library: MediaLibrary?
    @Environment(AppState.self) private var appState
    @State private var selectedSection: MusicSection = .artists

    enum MusicSection: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case albums = "Albums"
        case playlists = "Playlists"

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(MusicSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedSection {
            case .artists:
                ArtistListView(library: library)
            case .albums:
                AlbumListView(library: library)
            case .playlists:
                PlaylistListView()
            }
        }
        .navigationTitle("Music")
    }
}

#Preview {
    NavigationStack {
        MusicLibraryView(library: nil)
            .environment(AppState())
    }
}
