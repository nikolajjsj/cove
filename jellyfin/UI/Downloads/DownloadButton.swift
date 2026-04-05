import DownloadManager
import Models
import SwiftUI

/// A reusable download button that reflects the current download state for a media item
/// and allows the user to initiate, pause, resume, retry, or remove downloads.
///
/// Place this on album detail, movie detail, or episode row views. It queries
/// the `DownloadManagerService` for the item's current state and updates
/// its appearance accordingly.
///
/// ```swift
/// DownloadButton(
///     item: mediaItem,
///     serverId: connection.id,
///     downloadManager: manager
/// ) {
///     try await provider.downloadURL(for: mediaItem)
/// }
/// ```
struct DownloadButton: View {
    let item: MediaItem
    let serverId: String
    let downloadManager: DownloadManagerService
    let downloadURLResolver: @Sendable () async throws -> URL

    @State private var downloadItem: DownloadItem?
    @State private var isProcessing = false
    @State private var showRemoveConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Button {
            Task { await handleTap() }
        } label: {
            buttonLabel
        }
        .disabled(isProcessing)
        .confirmationDialog(
            "Remove Download?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive) {
                Task { await removeDownload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("'\(item.title)' will be removed from your device.")
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await refreshState()
        }
    }

    // MARK: - Button Label

    @ViewBuilder
    private var buttonLabel: some View {
        switch downloadItem?.state {
        case .none:
            // Not downloaded — show download arrow
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

        case .queued:
            // Queued — show clock with subtle animation
            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)

        case .downloading:
            // Actively downloading — circular progress with stop icon
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: downloadItem?.progress ?? 0)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "stop.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
            }
            .frame(width: 26, height: 26)

        case .paused:
            // Paused — show resume indicator
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

        case .completed:
            // Downloaded — green checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

        case .failed:
            // Failed — red error with retry affordance
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Tap Handling

    private func handleTap() async {
        guard !isProcessing else { return }

        switch downloadItem?.state {
        case .none:
            await startDownload()

        case .queued, .downloading:
            // Tapping an active/queued download pauses it
            await pauseDownload()

        case .paused:
            await resumeDownload()

        case .completed:
            // Tapping a completed download offers removal
            showRemoveConfirmation = true

        case .failed:
            await retryDownload()
        }
    }

    // MARK: - Download Actions

    private func startDownload() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
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
        } catch {
            showErrorMessage("Failed to start download: \(error.localizedDescription)")
        }
    }

    private func pauseDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.pauseDownload(id: id)
            await refreshState()
        } catch {
            showErrorMessage("Failed to pause: \(error.localizedDescription)")
        }
    }

    private func resumeDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.resumeDownload(id: id)
            await refreshState()
        } catch {
            showErrorMessage("Failed to resume: \(error.localizedDescription)")
        }
    }

    private func retryDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.retryDownload(id: id)
            await refreshState()
        } catch {
            showErrorMessage("Failed to retry: \(error.localizedDescription)")
        }
    }

    private func removeDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await downloadManager.deleteDownload(id: id)
            downloadItem = nil
        } catch {
            showErrorMessage("Failed to remove: \(error.localizedDescription)")
        }
    }

    // MARK: - State Refresh

    private func refreshState() async {
        do {
            downloadItem = try await downloadManager.download(
                for: item.id, serverId: serverId
            )
        } catch {
            // If we can't query state, leave the button in its current state.
            // This avoids flickering on transient errors.
        }
    }

    // MARK: - Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Convenience Initializer

extension DownloadButton {
    /// Creates a download button with a static URL instead of an async resolver.
    init(
        item: MediaItem,
        serverId: String,
        downloadManager: DownloadManagerService,
        downloadURL: URL
    ) {
        self.item = item
        self.serverId = serverId
        self.downloadManager = downloadManager
        self.downloadURLResolver = { downloadURL }
    }
}

// MARK: - Compact Variant

/// A smaller download button suitable for use in list rows (e.g. episode lists,
/// track rows). Shows just an icon without extra padding.
struct CompactDownloadButton: View {
    let item: MediaItem
    let serverId: String
    let downloadManager: DownloadManagerService
    let downloadURLResolver: @Sendable () async throws -> URL

    @State private var downloadItem: DownloadItem?
    @State private var isProcessing = false
    @State private var showRemoveConfirmation = false

    var body: some View {
        Button {
            Task { await handleTap() }
        } label: {
            compactLabel
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .confirmationDialog(
            "Remove Download?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await removeDownload() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await refreshState()
        }
    }

    @ViewBuilder
    private var compactLabel: some View {
        switch downloadItem?.state {
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.body)
                .foregroundStyle(.secondary)

        case .queued:
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.orange)

        case .downloading:
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: downloadItem?.progress ?? 0)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

        case .paused:
            Image(systemName: "pause.circle")
                .font(.body)
                .foregroundStyle(.orange)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)

        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.body)
                .foregroundStyle(.red)
        }
    }

    private func handleTap() async {
        guard !isProcessing else { return }

        switch downloadItem?.state {
        case .none:
            isProcessing = true
            defer { isProcessing = false }
            do {
                let url = try await downloadURLResolver()
                let result = try await downloadManager.enqueueDownload(
                    itemId: item.id,
                    serverId: serverId,
                    title: item.title,
                    mediaType: item.mediaType,
                    remoteURL: url
                )
                downloadItem = result
            } catch {
                // Silently fail in compact mode — the icon will remain unchanged
            }

        case .queued, .downloading:
            isProcessing = true
            defer { isProcessing = false }
            try? await downloadManager.pauseDownload(id: downloadItem?.id ?? "")
            await refreshState()

        case .paused:
            isProcessing = true
            defer { isProcessing = false }
            try? await downloadManager.resumeDownload(id: downloadItem?.id ?? "")
            await refreshState()

        case .completed:
            showRemoveConfirmation = true

        case .failed:
            isProcessing = true
            defer { isProcessing = false }
            try? await downloadManager.retryDownload(id: downloadItem?.id ?? "")
            await refreshState()
        }
    }

    private func removeDownload() async {
        guard let id = downloadItem?.id else { return }
        isProcessing = true
        defer { isProcessing = false }
        try? await downloadManager.deleteDownload(id: id)
        downloadItem = nil
    }

    private func refreshState() async {
        downloadItem = try? await downloadManager.download(
            for: item.id, serverId: serverId
        )
    }
}

// MARK: - Preview

#Preview("Download Button States") {
    VStack(spacing: 24) {
        // These are illustrative — in a real preview you'd supply mock managers.
        Text("Download button states are shown in-context on detail views.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}
