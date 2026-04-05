import Models
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            if let connection = appState.activeConnection {
                Section("Connected Server") {
                    LabeledContent("Name", value: connection.name)
                    LabeledContent("URL", value: connection.url.absoluteString)
                    LabeledContent("User ID", value: connection.userId)
                }
            }

            Section("Libraries") {
                if appState.libraries.isEmpty {
                    Text("No libraries found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.libraries) { library in
                        Label(library.name, systemImage: libraryIcon(for: library.collectionType))
                    }
                }
            }

            Section {
                Button("Disconnect", role: .destructive) {
                    Task { await appState.disconnect() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func libraryIcon(for type: CollectionType?) -> String {
        switch type {
        case .music: "music.note"
        case .movies: "film"
        case .tvshows: "tv"
        case .books: "book"
        case .playlists: "music.note.list"
        case .homevideos: "video"
        case .boxsets: "rectangle.stack"
        default: "folder"
        }
    }
}
