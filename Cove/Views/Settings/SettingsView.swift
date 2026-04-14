import Defaults
import DownloadManager
import Models
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Default(.downloadOverCellular) var downloadOverCellular
    @Default(.autoPlayNextEpisode) var autoPlayNextEpisode
    @Default(.forceLandscapeVideo) var forceLandscapeVideo
    @Default(.videoPlaybackSpeed) var videoPlaybackSpeed
    @Default(.skipForwardInterval) var skipForwardInterval
    @Default(.skipBackwardInterval) var skipBackwardInterval
    @Default(.autoSkipIntros) var autoSkipIntros
    @Default(.autoSkipCredits) var autoSkipCredits
    @Default(.accentColor) var accentColorName
    @Default(.wifiStreamingQuality) var wifiStreamingQuality
    @Default(.cellularStreamingQuality) var cellularStreamingQuality
    @Default(.resumePlaybackBehavior) var resumePlaybackBehavior
    @Default(.gridDensity) var gridDensity

    @Environment(AppState.self) private var appState
    @Environment(\.platformCapabilities) private var capabilities
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadCoordinator.self) private var downloadCoordinator
    @State private var showStorageManagement = false
    @State private var totalDownloadSize: Int64 = 0
    @State private var downloadCount: Int = 0

    private let playbackSpeedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let skipIntervalOptions: [Double] = [5, 10, 15, 30]

    private let accentColorOptions: [(name: String, value: String, color: Color)] = [
        ("Default", "default", .blue),
        ("Indigo", "indigo", .indigo),
        ("Purple", "purple", .purple),
        ("Pink", "pink", .pink),
        ("Red", "red", .red),
        ("Orange", "orange", .orange),
        ("Teal", "teal", .teal),
        ("Green", "green", .green),
    ]

    var body: some View {
        List {
            // MARK: - Connected Server

            if let connection = authManager.activeConnection {
                Section("Connected Server") {
                    LabeledContent("Name", value: connection.name)
                    LabeledContent("URL", value: connection.url.absoluteString)
                    Button("Disconnect", role: .destructive) {
                        Task { await appState.onDisconnect() }
                    }
                }
            }

            // MARK: - Libraries

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

            // MARK: - Appearance

            Section("Appearance") {
                Picker(selection: $accentColorName) {
                    ForEach(accentColorOptions, id: \.value) { option in
                        Label {
                            Text(option.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(option.color)
                        }
                        .tag(option.value)
                    }
                } label: {
                    Label("Accent Color", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)

                Picker(selection: $gridDensity) {
                    ForEach(GridDensity.allCases, id: \.self) { density in
                        Label(density.label, systemImage: density.icon)
                            .tag(density)
                    }
                } label: {
                    Label("Grid Density", systemImage: "square.grid.2x2")
                }
                .pickerStyle(.menu)
            }

            // MARK: - Downloads & Storage

            if downloadCoordinator.downloadManager != nil {
                Section("Downloads & Storage") {
                    Toggle(
                        "Download over Cellular", systemImage: "cellularbars",
                        isOn: $downloadOverCellular)

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
                            }
                        }
                    }
                }
            }

            // MARK: - Storage

            Section("Storage") {
                NavigationLink {
                    CacheManagementView()
                } label: {
                    Label("Manage Cache", systemImage: "externaldrive")
                }
            }

            // MARK: - Video Playback

            Section("Video Playback") {
                Picker(selection: $wifiStreamingQuality) {
                    ForEach(StreamingQuality.allCases, id: \.self) { quality in
                        Text(quality.label).tag(quality)
                    }
                } label: {
                    Label("WiFi Quality", systemImage: "wifi")
                }
                .pickerStyle(.menu)

                Picker(selection: $cellularStreamingQuality) {
                    ForEach(StreamingQuality.allCases, id: \.self) { quality in
                        Text(quality.label).tag(quality)
                    }
                } label: {
                    Label("Cellular Quality", systemImage: "cellularbars")
                }
                .pickerStyle(.menu)

                Toggle(
                    "Auto-play next episode", systemImage: "play.circle", isOn: $autoPlayNextEpisode
                )

                Toggle("Auto-skip intros", systemImage: "forward.fill", isOn: $autoSkipIntros)
                Toggle("Auto-skip credits", systemImage: "forward.end.fill", isOn: $autoSkipCredits)

                Picker(selection: $resumePlaybackBehavior) {
                    ForEach(ResumePlaybackBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                } label: {
                    Label("Resume Behavior", systemImage: "memories")
                }
                .pickerStyle(.menu)

                if capabilities.supportsOrientationLock {
                    Toggle(
                        "Force landscape", systemImage: "rectangle.landscape.rotate",
                        isOn: $forceLandscapeVideo)
                }

                Picker(selection: $videoPlaybackSpeed) {
                    ForEach(playbackSpeedOptions, id: \.self) { speed in
                        if speed == 1.0 {
                            Text("1× (Normal)").tag(speed)
                        } else {
                            Text("\(speed, specifier: "%g")×").tag(speed)
                        }
                    }
                } label: {
                    Label("Default playback speed", systemImage: "gauge.with.needle")
                }
                .pickerStyle(.menu)

                Picker(selection: $skipForwardInterval) {
                    ForEach(skipIntervalOptions, id: \.self) { interval in
                        Text("\(Int(interval))s").tag(interval)
                    }
                } label: {
                    Label("Skip forward interval", systemImage: "goforward")
                }
                .pickerStyle(.menu)

                Picker(selection: $skipBackwardInterval) {
                    ForEach(skipIntervalOptions, id: \.self) { interval in
                        Text("\(Int(interval))s").tag(interval)
                    }
                } label: {
                    Label("Skip backward interval", systemImage: "gobackward")
                }
                .pickerStyle(.menu)
            }

            // MARK: - Subtitles

            Section("Subtitles") {
                NavigationLink {
                    SubtitleSettingsView()
                } label: {
                    Label("Subtitle Appearance", systemImage: "captions.bubble")
                }
            }

            // MARK: - About

            Section("About") {
                LabeledContent("App", value: "Cove")

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                    as? String,
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
            }
        }
        .task {
            await loadStorageInfo()
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
