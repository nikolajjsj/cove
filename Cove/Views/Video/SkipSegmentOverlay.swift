import Defaults
import Models
import PlaybackEngine
import SwiftUI

// MARK: - Skip Segment Overlay

/// Reads `videoManager.currentTime` in its own tracking scope to compute the
/// active skippable segment without triggering `VideoPlayerView.body` re-evaluation.
struct SkipSegmentOverlay: View {
    let mediaSegments: [MediaSegment]
    let videoManager: VideoPlaybackManager

    @Default(.autoSkipIntros) private var autoSkipIntros
    @Default(.autoSkipCredits) private var autoSkipCredits
    @State private var autoSkippedSegments: Set<String> = []

    private var activeSegment: MediaSegment? {
        mediaSegments.first { $0.contains(time: videoManager.currentTime) }
    }

    var body: some View {
        SkipSegmentButton(
            segment: shouldShowManualButton ? activeSegment : nil,
            isHidden: videoManager.showNextEpisodeCountdown,
            onSkip: { endTime in videoManager.seek(to: endTime) }
        )
        .onChange(of: activeSegment?.id) { _, newValue in
            guard let segment = activeSegment,
                let id = newValue,
                !autoSkippedSegments.contains(id),
                shouldAutoSkip(segment)
            else { return }
            autoSkippedSegments.insert(id)
            videoManager.seek(to: segment.endTime)
        }
    }

    private var shouldShowManualButton: Bool {
        guard let segment = activeSegment else { return false }
        return !shouldAutoSkip(segment)
    }

    private func shouldAutoSkip(_ segment: MediaSegment) -> Bool {
        switch segment.type {
        case .intro:
            return autoSkipIntros
        case .outro, .credits:
            return autoSkipCredits
        default:
            return false
        }
    }
}
