import DownloadManager
import Models
import SwiftUI

// MARK: - Shared Download Button State

/// Shared state and logic for download button variants.
/// Manages the download lifecycle (enqueue, pause, resume, retry, delete)
/// and keeps the UI in sync with the current `DownloadItem` state.
@Observable
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

// MARK: - Download Button

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
    @State private var model: DownloadButtonModel

    init(
        item: MediaItem,
        serverId: String,
        downloadManager: DownloadManagerService,
        downloadURLResolver: @escaping @Sendable () async throws -> URL,
        onDownload: (@Sendable () async throws -> Void)? = nil
    ) {
        _model = State(
            initialValue: DownloadButtonModel(
                item: item,
                serverId: serverId,
                downloadManager: downloadManager,
                downloadURLResolver: downloadURLResolver,
                onDownload: onDownload
            ))
    }

    var body: some View {
        Button {
            Task { await model.handleTap() }
        } label: {
            buttonLabel
        }
        .disabled(model.isProcessing)
        .confirmationDialog(
            "Remove Download?",
            isPresented: $model.showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive) {
                Task { await model.removeDownload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("'\(model.item.title)' will be removed from your device.")
        }
        .alert("Download Error", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await model.refreshState()
        }
        .task(id: model.state) {
            // Poll for progress updates while actively downloading
            guard model.state == .downloading || model.state == .queued else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await model.refreshState()
            }
        }
    }

    // MARK: - Button Label

    @ViewBuilder
    private var buttonLabel: some View {
        switch model.state {
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
                    .trim(from: 0, to: model.progress)
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
}

// MARK: - Convenience Initializer

extension DownloadButton {
    /// Creates a download button with a static URL instead of an async resolver.
    init(
        item: MediaItem,
        serverId: String,
        downloadManager: DownloadManagerService,
        downloadURL: URL,
        onDownload: (@Sendable () async throws -> Void)? = nil
    ) {
        self.init(
            item: item,
            serverId: serverId,
            downloadManager: downloadManager,
            downloadURLResolver: { downloadURL },
            onDownload: onDownload
        )
    }
}

// MARK: - Compact Variant

/// A smaller download button suitable for use in list rows (e.g. episode lists,
/// track rows). Shows just an icon without extra padding.
struct CompactDownloadButton: View {
    @State private var model: DownloadButtonModel

    init(
        item: MediaItem,
        serverId: String,
        downloadManager: DownloadManagerService,
        downloadURLResolver: @escaping @Sendable () async throws -> URL,
        onDownload: (@Sendable () async throws -> Void)? = nil
    ) {
        _model = State(
            initialValue: DownloadButtonModel(
                item: item,
                serverId: serverId,
                downloadManager: downloadManager,
                downloadURLResolver: downloadURLResolver,
                onDownload: onDownload
            ))
    }

    var body: some View {
        Button {
            Task { await model.handleTap() }
        } label: {
            compactLabel
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isProcessing)
        .confirmationDialog(
            "Remove Download?",
            isPresented: $model.showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await model.removeDownload() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await model.refreshState()
        }
        .task(id: model.state) {
            // Poll for progress updates while actively downloading
            guard model.state == .downloading || model.state == .queued else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await model.refreshState()
            }
        }
    }

    @ViewBuilder
    private var compactLabel: some View {
        switch model.state {
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
                    .trim(from: 0, to: model.progress)
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
}

// MARK: - Preview

#Preview("Download Button States") {
    VStack(spacing: 24) {
        Text("Download button states are shown in-context on detail views.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}
