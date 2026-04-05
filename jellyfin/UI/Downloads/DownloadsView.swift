import DownloadManager
import Models
import SwiftUI

/// The main downloads tab view. Displays all downloads grouped by state (active,
/// paused, completed, failed) and by media type within the completed section.
struct DownloadsView: View {
    let downloadManager: DownloadManagerService

    @Environment(AppState.self) private var appState
    @State private var downloads: [DownloadItem] = []
    @State private var isLoading = true
    @State private var showStorageManagement = false
    @State private var itemToDelete: DownloadItem?
    @State private var showDeleteAllConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading downloads…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if downloads.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text(
                        "Download music, movies, and episodes to enjoy offline."
                    )
                )
            } else {
                downloadsList
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showStorageManagement = true
                    } label: {
                        Label("Storage", systemImage: "internaldrive")
                    }

                    if !downloads.isEmpty {
                        Divider()

                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showStorageManagement) {
            NavigationStack {
                StorageManagementView(downloadManager: downloadManager)
            }
        }
        .alert("Delete Download?", isPresented: showDeleteBinding) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { await performDelete(item) }
                    itemToDelete = nil
                }
            }
        } message: {
            if let item = itemToDelete {
                Text(""\(item.title)" will be removed from your device.")
            }
        }
        .confirmationDialog(
            "Delete All Downloads?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await performDeleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All downloaded media will be removed from your device. This cannot be undone."
            )
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                errorBanner(errorMessage)
            }
        }
        .task {
            await loadDownloads()
        }
        .refreshable {
            await loadDownloads()
        }
    }

    // MARK: - Downloads List

    private var downloadsList: some View {
        List {
            // Active downloads (downloading + queued)
            let active = downloads.filter {
                $0.state == .downloading || $0.state == .queued
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { item in
                        DownloadRowView(item: item, onAction: handleAction)
                    }
                } header: {
                    activeSectionHeader(count: active.count)
                }
            }

            // Paused downloads
            let paused = downloads.filter { $0.state == .paused }
            if !paused.isEmpty {
                Section("Paused") {
                    ForEach(paused) { item in
                        DownloadRowView(item: item, onAction: handleAction)
                    }
                }
            }

            // Completed downloads, grouped by media type
            let completed = downloads.filter { $0.state == .completed }
            if !completed.isEmpty {
                let grouped = Dictionary(grouping: completed, by: \.mediaType)
                let sortedKeys = grouped.keys.sorted { $0.rawValue < $1.rawValue }

                ForEach(sortedKeys, id: \.self) { type in
                    Section(sectionTitle(for: type)) {
                        ForEach(grouped[type] ?? []) { item in
                            DownloadRowView(item: item, onAction: handleAction)
                        }
                        .onDelete { indexSet in
                            let items = grouped[type] ?? []
                            Task {
                                for index in indexSet {
                                    guard items.indices.contains(index) else { continue }
                                    await performDelete(items[index])
                                }
                            }
                        }
                    }
                }
            }

            // Failed downloads
            let failed = downloads.filter { $0.state == .failed }
            if !failed.isEmpty {
                Section {
                    ForEach(failed) { item in
                        DownloadRowView(item: item, onAction: handleAction)
                    }
                } header: {
                    HStack {
                        Text("Failed")
                        Spacer()
                        if failed.count > 1 {
                            Button("Retry All") {
                                Task { await retryAllFailed(failed) }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: downloads.map(\.id))
    }

    // MARK: - Section Headers & Titles

    private func activeSectionHeader(count: Int) -> some View {
        HStack {
            Text("Active")
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    private func sectionTitle(for type: MediaType) -> String {
        switch type {
        case .movie: "Movies"
        case .episode: "Episodes"
        case .track: "Music"
        case .album: "Albums"
        case .series: "Series"
        case .season: "Seasons"
        case .artist: "Artists"
        case .playlist: "Playlists"
        case .book: "Books"
        case .podcast: "Podcasts"
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.red, in: RoundedRectangle(cornerRadius: 10))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { errorMessage = nil }
                }
            }
    }

    // MARK: - Action Handling

    private func handleAction(_ action: DownloadAction, _ item: DownloadItem) {
        Task {
            do {
                switch action {
                case .pause:
                    try await downloadManager.pauseDownload(id: item.id)
                case .resume:
                    try await downloadManager.resumeDownload(id: item.id)
                case .retry:
                    try await downloadManager.retryDownload(id: item.id)
                case .delete:
                    itemToDelete = item
                    return // Don't reload yet — wait for confirmation
                case .play:
                    // Playback integration will be wired in a later phase.
                    // For now this is a no-op; the row tap is handled here
                    // so the UI is ready when playback routing is added.
                    return
                }
                await loadDownloads()
            } catch {
                withAnimation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDelete(_ item: DownloadItem) async {
        do {
            try await downloadManager.deleteDownload(id: item.id)
            await loadDownloads()
        } catch {
            withAnimation {
                errorMessage = "Failed to delete "\(item.title)": \(error.localizedDescription)"
            }
        }
    }

    private func performDeleteAll() async {
        guard let serverId = appState.activeConnection?.id else { return }
        do {
            try await downloadManager.deleteAllDownloads(serverId: serverId)
            await loadDownloads()
        } catch {
            withAnimation {
                errorMessage = "Failed to delete downloads: \(error.localizedDescription)"
            }
        }
    }

    private func retryAllFailed(_ items: [DownloadItem]) async {
        for item in items {
            try? await downloadManager.retryDownload(id: item.id)
        }
        await loadDownloads()
    }

    // MARK: - Data Loading

    private func loadDownloads() async {
        do {
            let all = try await downloadManager.allDownloads()
            // If authenticated, filter to active server; otherwise show everything
            if let serverId = appState.activeConnection?.id {
                downloads = all.filter { $0.serverId == serverId }
            } else {
                downloads = all
            }
        } catch {
            downloads = []
            withAnimation {
                errorMessage = "Could not load downloads."
            }
        }
        isLoading = false
    }

    // MARK: - Helpers

    private var showDeleteBinding: Binding<Bool> {
        Binding(
            get: { itemToDelete != nil },
            set: { newValue in
                if !newValue { itemToDelete = nil }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DownloadsView(
            downloadManager: .previewMock
        )
        .environment(AppState())
    }
}

// MARK: - Preview Helpers

extension DownloadManagerService {
    /// A placeholder used only for SwiftUI previews. The preview will show the
    /// empty-state because the mock repository contains no data.
    fileprivate static var previewMock: DownloadManagerService {
        // The initializer requires concrete repository instances. In a real
        // preview you would supply in-memory fakes. For now we rely on the
        // view's empty-state rendering, so this is intentionally a fatalError
        // sentinel that is never actually called at preview-render time.
        fatalError("Replace with a real mock when preview repositories are available")
    }
}
