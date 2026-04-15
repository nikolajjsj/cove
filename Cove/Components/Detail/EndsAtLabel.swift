import Models
import SwiftUI

/// A subtle label that shows when playback will finish if started now.
///
/// Calculates the end time based on the item's runtime and any existing
/// resume position. If the user has partially watched the item, the
/// remaining time is used instead of the full runtime.
///
/// ```swift
/// EndsAtLabel(item: item)
/// ```
struct EndsAtLabel: View {
    let item: MediaItem

    var body: some View {
        if let endTime {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)

                Text("Ends at \(endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - End Time Calculation

    /// The projected end time if playback starts now.
    ///
    /// Uses the remaining duration (runtime minus resume position) when the
    /// user has partially watched the item, otherwise uses the full runtime.
    /// Returns `nil` when runtime is unavailable or zero.
    private var endTime: Date? {
        guard let runtime = item.runtime, runtime > 0 else { return nil }

        let resumePosition = item.userData?.playbackPosition ?? 0
        let remaining = max(runtime - resumePosition, 0)

        guard remaining > 0 else { return nil }

        return Date.now.addingTimeInterval(remaining)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Ends At — Full Movie") {
        VStack(spacing: 12) {
            EndsAtLabel(
                item: MediaItem(
                    id: ItemID("1"),
                    title: "Test Movie",
                    mediaType: .movie,
                    runTimeTicks: 7200 * 10_000_000  // 2 hours
                )
            )

            EndsAtLabel(
                item: MediaItem(
                    id: ItemID("2"),
                    title: "Resumed Movie",
                    mediaType: .movie,
                    runTimeTicks: 7200 * 10_000_000,  // 2 hours
                    userData: UserData(
                        isFavorite: false,
                        playbackPosition: 3600,  // 1 hour in
                        playCount: 0,
                        isPlayed: false
                    )
                )
            )
        }
        .padding()
    }
#endif
