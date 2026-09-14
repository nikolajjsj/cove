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
    /// On-disk bytes per media type, measured from the file system.
    @State private var bytesByType: [MediaType: Int64] = [:]
    /// Bytes on disk not attributable to a completed download's own directory —
    /// parent artwork (series/season/album posters) and staging leftovers.
    @State private var otherBytes: Int64 = 0
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
        .inlineNavigationTitle()
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
                    "Downloads use \(percentage.formatted(.number.precision(.fractionLength(1))))% of available storage."
                )
            }
        }
    }

    /// A visual bar showing the proportion of storage consumed by downloads.
    private var storageBar: some View {
        let total = max(totalUsedBytes + availableBytes, 1)
        let fraction = CGFloat(totalUsedBytes) / CGFloat(total)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)

            RoundedRectangle(cornerRadius: 4)
                .fill(.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: max(fraction, fraction > 0 ? 0.02 : 0), anchor: .leading)
        }
        .frame(height: 8)
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    }

    // MARK: - Breakdown by Media Type

    private var breakdownSection: some View {
        Section {
            if completedDownloads.isEmpty {
                Text("No completed downloads")
                    .foregroundStyle(.secondary)
            } else {
                let grouped = Dictionary(grouping: completedDownloads, by: \.mediaType)
                let sortedKeys = grouped.keys.sorted { $0.rawValue < $1.rawValue }

                ForEach(sortedKeys, id: \.self) { type in
                    let items = grouped[type] ?? []
                    let typeBytes = bytesByType[type] ?? 0

                    HStack {
                        Image(systemName: type.placeholderIcon)
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

                // Everything on disk that isn't inside a completed item's own
                // directory: parent artwork and staging leftovers. Listing it
                // keeps the rows adding up to "Used by Downloads".
                if otherBytes > 0 {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Artwork & Other")
                                .font(.body)
                            Text("Posters and cached extras")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(formattedBytes(otherBytes))
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
        } header: {
            Text("Downloaded Items")
        } footer: {
            if hasInProgressDownloads {
                Text(
                    "In-progress downloads are held in temporary storage and aren't counted above until they finish."
                )
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

            // Clean up orphaned metadata and artwork before measuring storage.
            // This ensures the displayed size reflects only data that is actually
            // associated with a known download record.
            let serverIds = Set(downloads.map(\.serverId))
            for serverId in serverIds {
                await downloadManager.cleanupOrphanedMetadata(serverId: serverId)
            }

            let usage = await Self.measureDiskUsage(for: completedDownloads)
            totalUsedBytes = usage.total
            availableBytes = usage.available
            bytesByType = usage.byType
            otherBytes = max(0, usage.total - usage.byType.values.reduce(0, +))
        } catch {
            downloads = []
            errorMessage = error.localizedDescription
        }
    }

    /// Measure on-disk usage off the main actor — walking the downloads tree
    /// touches the file system once per item and must not block the UI.
    private static func measureDiskUsage(
        for items: [DownloadItem]
    ) async -> (total: Int64, available: Int64, byType: [MediaType: Int64]) {
        await Task.detached(priority: .utility) {
            let storage = DownloadStorage.shared
            var byType: [MediaType: Int64] = [:]
            for item in items {
                byType[item.mediaType, default: 0] += (try? storage.diskUsage(for: item)) ?? 0
            }
            return (
                total: (try? storage.totalDiskUsage()) ?? 0,
                available: (try? storage.availableDiskSpace()) ?? 0,
                byType: byType
            )
        }.value
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

    private var hasInProgressDownloads: Bool {
        downloads.contains {
            $0.state == .queued || $0.state == .downloading || $0.state == .paused
        }
    }

    // MARK: - Helpers

    private func formattedBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    private func sectionTitle(for type: MediaType) -> String {
        switch type {
        case .movie: "Movies"
        case .episode: "Episodes"
        case .series: "Series"
        case .season: "Seasons"
        case .book: "Books"
        case .podcast: "Podcasts"
        case .collection: "Collections"
        case .genre: "Genres"
        case .studio: "Studios"
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
