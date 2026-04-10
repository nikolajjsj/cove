import DownloadManager
import Models
import SwiftUI

// MARK: - Shared Download Button State

/// Shared state and logic for download button variants.
/// Manages the download lifecycle (enqueue, pause, resume, retry, delete)
/// and keeps the UI in sync with the current `DownloadItem` state.
@Observable
@MainActor
final class DownloadButtonModel {
    let item: MediaItem
    let serverId: String
    let downloadManager: DownloadManagerService
    let downloadURLResolver: @Sendable () async throws -> URL
    let onDownload: (@Sendable () async throws -> Void)?

    private(set) var downloadItem: DownloadItem?
    private(set) var isProcessing = false
    var showRemoveConfirmation = false
    var errorMessage: String?
    var showError = false

    var state: DownloadState? { downloadItem?.state }
    var progress: Double { downloadItem?.progress ?? 0 }

    init(
        item: MediaItem,
        serverId: String,
        downloadManager: DownloadManagerService,
        downloadURLResolver: @escaping @Sendable () async throws -> URL,
        onDownload: (@Sendable () async throws -> Void)? = nil
    ) {
        self.item = item
        self.serverId = serverId
        self.downloadManager = downloadManager
        self.downloadURLResolver = downloadURLResolver
        self.onDownload = onDownload
    }

    func handleTap() async {
        guard !isProcessing else { return }

        switch downloadItem?.state {
        case .none:
            await startDownload()
        case .queued, .downloading:
            // Streaming/transcoded downloads can't be paused — they would lose
            // all progress because the server doesn't support HTTP range requests.
            if downloadItem?.isResumable == false {
                return
            }
            await pauseDownload()
        case .paused:
            await resumeDownload()
        case .completed:
            showRemoveConfirmation = true
        case .failed:
            await retryDownload()
        }
    }

    func refreshState() async {
        do {
            downloadItem = try await downloadManager.download(
                for: item.id, serverId: serverId
            )
        } catch {
            // If we can't query state, leave the button in its current state.
            // This avoids flickering on transient errors.
        }
    }

    func startDownload() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            if let onDownload {
                try await onDownload()
                await refreshState()
            } else {
                let url = try await downloadURLResolver()
                let result = try await downloadManager.enqueueDownload(
                    itemId: item.id,
                    serverId: serverId,
                    title: item.title,
                    mediaType: item.mediaType,
                    remoteURL: url,
                    parentId: nil,
                    artworkURL: nil
                )
                downloadItem = result
            }
        } catch {
            setError("Failed to start download: \(error.localizedDescription)")
        }
    }

    func pauseDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.pauseDownload(id: id)
            await refreshState()
        } catch {
            setError("Failed to pause: \(error.localizedDescription)")
        }
    }

    func resumeDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.resumeDownload(id: id)
            await refreshState()
        } catch {
            setError("Failed to resume: \(error.localizedDescription)")
        }
    }

    func retryDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.retryDownload(id: id)
            await refreshState()
        } catch {
            setError("Failed to retry: \(error.localizedDescription)")
        }
    }

    func removeDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.deleteDownload(id: id)
            downloadItem = nil
        } catch {
            setError("Failed to remove: \(error.localizedDescription)")
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
