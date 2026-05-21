import Models
import SwiftUI

// MARK: - Skip Segment Button

/// A floating "Skip Intro" / "Skip Credits" button that appears when playback
/// enters a skippable media segment.
struct SkipSegmentButton: View {
    let segment: MediaSegment?
    let isHidden: Bool
    let onSkip: (TimeInterval) -> Void

    var body: some View {
        if let segment, !isHidden {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        onSkip(segment.endTime)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "forward.fill")
                                .font(.subheadline)
                            Text(segment.skipButtonLabel)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                .padding(.trailing, 24)
                .padding(.bottom, 100)
            }
            .animation(.spring(duration: 0.4), value: segment.id)
        }
    }
}
