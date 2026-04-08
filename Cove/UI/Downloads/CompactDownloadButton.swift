import DownloadManager
import Models
import SwiftUI

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
