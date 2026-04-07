import Defaults
import DownloadManager
import Models
import SwiftUI

struct SettingsView: View {
    @Default(.downloadOverCellular) var downloadOverCellular
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @State private var showStorageManagement = false
    @State private var totalDownloadSize: Int64 = 0
    @State private var downloadCount: Int = 0

    var body: some View {
        NavigationStack {
            List {
                if let connection = authManager.activeConnection {
                    Section("Connected Server") {
                        LabeledContent("Name", value: connection.name)
                        LabeledContent("URL", value: connection.url.absoluteString)
                        Button("Disconnect", role: .destructive) {
                            Task { await appState.onDisconnect() }
                        }
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
                
                if downloadCoordinator.downloadManager != nil {
                    Section("Downloads & Storage") {
                        Toggle("Download over Cellular", systemImage: "cellularbars", isOn: $downloadOverCellular)
                        
                        if let downloadManager = downloadCoordinator.downloadManager {
                            NavigationLink {
                                StorageManagementView(downloadManager: downloadManager)
                            } label: {
                                HStack {
                                    Label("Manage Storage", systemImage: "internaldrive")
                                    Spacer()
                                    if totalDownloadSize > 0 {
                                        Text(
                                            ByteCountFormatter.string(
                                                fromByteCount: totalDownloadSize,
                                                countStyle: .file
                                            )
                                        )
                                        .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await loadStorageInfo()
            }
        }
    }

    // MARK: - Helpers

    private func loadStorageInfo() async {
        guard let downloadManager = downloadCoordinator.downloadManager,
            let connection = authManager.activeConnection
        else { return }

        do {
            totalDownloadSize = try await downloadManager.totalStorageUsed(
                serverId: connection.id.uuidString
            )
            let downloads = try await downloadManager.downloads(
                for: connection.id.uuidString
            )
            downloadCount = downloads.filter { $0.state == .completed }.count
        } catch {
            // Non-critical — just show nothing
        }
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
