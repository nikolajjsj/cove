import DownloadManager
import Models
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showStorageManagement = false
    @State private var totalDownloadSize: Int64 = 0
    @State private var downloadCount: Int = 0

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

            if let _ = appState.downloadManager {
                Section("Downloads & Storage") {
                    Button {
                        showStorageManagement = true
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
                    .tint(.primary)

                    if downloadCount > 0 {
                        LabeledContent(
                            "Downloaded Items",
                            value: "\(downloadCount)"
                        )
                    }

                    networkStatusRow
                }
            }

            Section {
                Button("Disconnect", role: .destructive) {
                    Task { await appState.disconnect() }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showStorageManagement) {
            if let downloadManager = appState.downloadManager {
                NavigationStack {
                    StorageManagementView(downloadManager: downloadManager)
                }
            }
        }
        .task {
            await loadStorageInfo()
        }
    }

    // MARK: - Network Status

    private var networkStatusRow: some View {
        HStack {
            Label("Network", systemImage: networkIcon)
            Spacer()
            Text(networkStatusText)
                .foregroundStyle(.secondary)
        }
    }

    private var networkIcon: String {
        if !appState.networkMonitor.isConnected {
            return "wifi.slash"
        } else if appState.networkMonitor.isExpensive {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "wifi"
        }
    }

    private var networkStatusText: String {
        if !appState.networkMonitor.isConnected {
            return "Offline"
        } else if appState.networkMonitor.isExpensive {
            return "Cellular"
        } else {
            return "Connected"
        }
    }

    // MARK: - Helpers

    private func loadStorageInfo() async {
        guard let downloadManager = appState.downloadManager,
            let connection = appState.activeConnection
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
