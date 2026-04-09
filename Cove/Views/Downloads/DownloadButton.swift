import DownloadManager
import Models
import SwiftUI

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
