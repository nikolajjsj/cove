import DownloadManager
import Models
import SwiftUI

/// Shows a breakdown of storage used by offline downloads and allows the user
/// to inspect per-type usage and bulk-delete downloaded content.
struct StorageManagementView: View {
    let downloadManager: DownloadManagerService

    @Environment(\.dismiss) private var dismiss
    @State private var downloads: [DownloadItem] = []
    @State private var totalUsedBytes: Int64 = 0
    @State private var availableBytes: Int64 = 0
    @State private var isLoading = true
    @State private var showDeleteAllConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                storageOverviewSection
                breakdownSection
                actionsSection
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Delete All Downloads?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Downloads", role: .destructive) {
                Task { await deleteAllDownloads() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All downloaded media will be removed from your device. This action cannot be undone."
            )
        }
        .task {
            await loadStorageInfo()
        }
    }

    // MARK: - Storage Overview

    private var storageOverviewSection: some View {
        Section {
            storageBar

            LabeledContent(
                "Used by Downloads",
                value: formattedBytes(totalUsedBytes)
            )

            LabeledContent(
                "Available on Device",
                value: formattedBytes(availableBytes)
            )

            if !downloads.isEmpty {
                LabeledContent(
                    "Total Items",
                    value: "\(completedDownloads.count)"
                )
            }
        } header: {
            Text("Storage")
        } footer: {
            if totalUsedBytes > 0, availableBytes > 0 {
                let total = totalUsedBytes + availableBytes
                let percentage = Double(totalUsedBytes) / Double(total) * 100
                Text(
                    "Downloads use \(String(format: "%.1f", percentage))% of available storage."
                )
            }
        }
    }

    /// A visual bar showing the proportion of storage consumed by downloads.
    private var storageBar: some View {
        GeometryReader { geometry in
            let total = max(totalUsedBytes + availableBytes, 1)
            let fraction = CGFloat(totalUsedBytes) / CGFloat(total)
            let barWidth = max(geometry.size.width * fraction, fraction > 0 ? 4 : 0)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: 4)
                    .fill(.tint)
                    .frame(width: barWidth)
            }
        }
        .frame(height: 8)
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }

    // MARK: - Breakdown by Media Type

    private var breakdownSection: some View {
        Section("Downloaded Items") {
            if completedDownloads.isEmpty {
                Text("No completed downloads")
                    .foregroundStyle(.secondary)
            } else {
                let grouped = Dictionary(grouping: completedDownloads, by: \.mediaType)
                let sortedKeys = grouped.keys.sorted { $0.rawValue < $1.rawValue }

                ForEach(sortedKeys, id: \.self) { type in
                    let items = grouped[type] ?? []
                    let typeBytes = items.reduce(Int64(0)) { $0 + $1.totalBytes }

                    HStack {
                        Image(systemName: iconName(for: type))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sectionTitle(for: type))
                                .font(.body)
                            Text(
                                "\(items.count) \(items.count == 1 ? "item" : "items")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(formattedBytes(typeBytes))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // In-progress items (queued, downloading, paused)
                let inProgress = downloads.filter {
                    $0.state == .queued || $0.state == .downloading || $0.state == .paused
                }
                if !inProgress.isEmpty {
                    let inProgressBytes = inProgress.reduce(Int64(0)) {
                        $0 + $1.downloadedBytes
                    }
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("In Progress")
                                .font(.body)
                            Text(
                                "\(inProgress.count) \(inProgress.count == 1 ? "item" : "items")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(formattedBytes(inProgressBytes))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        if !downloads.isEmpty {
            Section {
                Button("Delete All Downloads", role: .destructive) {
                    showDeleteAllConfirmation = true
                }
            } footer: {
                Text(
                    "Removes all downloaded media from this device. You can re-download items anytime you're connected to your server."
                )
            }
        }
    }

    // MARK: - Data Loading

    private func loadStorageInfo() async {
        isLoading = true
        defer { isLoading = false }

        do {
            downloads = try await downloadManager.allDownloads()

            let storage = DownloadStorage.shared
            totalUsedBytes = (try? storage.totalDiskUsage()) ?? 0
            availableBytes = (try? storage.availableDiskSpace()) ?? 0
        } catch {
            downloads = []
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllDownloads() async {
        // Collect unique server IDs from all downloads and delete per-server
        let serverIds = Set(downloads.map(\.serverId))
        for serverId in serverIds {
            try? await downloadManager.deleteAllDownloads(serverId: serverId)
        }
        await loadStorageInfo()
    }

    // MARK: - Computed Properties

    private var completedDownloads: [DownloadItem] {
        downloads.filter { $0.state == .completed }
    }

    // MARK: - Helpers

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    private func iconName(for type: MediaType) -> String {
        switch type {
        case .movie: "film"
        case .episode: "tv"
        case .track: "music.note"
        case .album: "square.stack"
        case .series: "tv.and.mediabox"
        case .season: "list.and.film"
        case .artist: "music.mic"
        case .playlist: "music.note.list"
        case .book: "book"
        case .podcast: "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StorageManagementView(
            downloadManager: {
                fatalError("Preview requires mock DownloadManagerService")
            }()
        )
    }
}
