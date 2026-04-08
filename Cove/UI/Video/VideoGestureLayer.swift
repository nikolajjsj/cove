import AVFoundation
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// A transparent overlay that handles all video player gesture interactions.
///
/// All gestures are composed on a **single** hit-testable surface so that SwiftUI
/// can properly disambiguate between taps, drags, and pinches.
///
/// Gestures supported:
/// - **Single tap**: Toggle controls visibility
/// - **Double tap left half**: Skip backward
/// - **Double tap right half**: Skip forward
/// - **Horizontal drag**: Scrub through the timeline
/// - **Pinch**: Cycle between fit/fill aspect ratios (iOS)
struct VideoGestureLayer: View {
    // MARK: - Configuration

    let currentTime: TimeInterval
    let duration: TimeInterval
    let skipForwardInterval: TimeInterval
    let skipBackwardInterval: TimeInterval
    let onToggleControls: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void
    let onSeekStarted: () -> Void
    let onSeekChanged: (TimeInterval) -> Void
    let onSeekCommitted: (TimeInterval) -> Void
    let onAspectRatioCycle: () -> Void

    // MARK: - Internal State

    /// Which side of the screen was double-tapped (for the ripple animation).
    @State private var skipSide: SkipSide? = nil
    @State private var skipAnimationTask: Task<Void, Never>? = nil
    /// How many consecutive skips in the same direction (for accumulation display).
    @State private var skipCount: Int = 0

    /// Drag gesture tracking
    @State private var isDragging = false
    @State private var dragType: DragType? = nil
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dragSeekTime: TimeInterval = 0

    /// Pinch gesture state
    @State private var isPinching = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // MARK: - Single unified gesture surface
                //
                // All interactive gestures live on ONE view so SwiftUI can
                // disambiguate them correctly.

                Color.clear
                    .contentShape(Rectangle())
                    // Double-tap (count: 2) must be declared BEFORE single-tap
                    // so SwiftUI gives it priority and waits to disambiguate.
                    .onTapGesture(count: 2, coordinateSpace: .local) { location in
                        if location.x < geo.size.width / 2 {
                            triggerSkip(.backward)
                        } else {
                            triggerSkip(.forward)
                        }
                    }
                    .onTapGesture(count: 1) {
                        onToggleControls()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                handleDragChanged(value: value, in: geo.size)
                            }
                            .onEnded { value in
                                handleDragEnded(value: value)
                            }
                    )
                    #if os(iOS)
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { _ in
                                    isPinching = true
                                }
                                .onEnded { value in
                                    if value.magnification > 1.15
                                        || value.magnification < 0.85
                                    {
                                        onAspectRatioCycle()
                                    }
                                    isPinching = false
                                }
                        )
                    #endif

                // MARK: - Skip animation overlays

                if let side = skipSide {
                    skipOverlay(side: side, in: geo.size)
                        .allowsHitTesting(false)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.12)),
                                removal: .opacity.animation(.easeIn(duration: 0.25))
                            )
                        )
                }

                // MARK: - Seek scrub indicator

                if isDragging, dragType == .horizontalSeek {
                    seekIndicator
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: skipSide)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
        }
    }

    // MARK: - Skip Logic

    private func triggerSkip(_ side: SkipSide) {
        skipAnimationTask?.cancel()

        if skipSide == side {
            // Same direction — accumulate
            skipCount += 1
        } else {
            // New direction — reset
            skipSide = side
            skipCount = 1
        }

        switch side {
        case .forward: onSkipForward()
        case .backward: onSkipBackward()
        }

        skipAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled {
                skipSide = nil
                skipCount = 0
            }
        }
    }

    // MARK: - Skip Overlay (YouTube-style)

    @ViewBuilder
    private func skipOverlay(side: SkipSide, in size: CGSize) -> some View {
        let isForward = side == .forward
        let interval = isForward ? skipForwardInterval : skipBackwardInterval
        let totalSeconds = Int(interval) * skipCount

        ZStack {
            // D-shaped translucent backdrop — a large circle positioned at the edge
            // so only the inner half is visible, creating a smooth semicircle.
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: size.height * 1.1, height: size.height * 1.1)
                .position(
                    x: isForward ? size.width : 0,
                    y: size.height / 2
                )

            // Chevrons + seconds label
            VStack(spacing: 10) {
                chevronWave(forward: isForward)

                Text("\(totalSeconds) seconds")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .position(
                x: isForward ? size.width * 0.78 : size.width * 0.22,
                y: size.height / 2
            )
        }
        .clipShape(Rectangle())
    }

    /// Three animated chevrons that light up sequentially in a wave pattern.
    @ViewBuilder
    private func chevronWave(forward: Bool) -> some View {
        PhaseAnimator(
            [0, 1, 2],
            trigger: skipCount
        ) { phase in
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let isBright: Bool = forward ? (i <= phase) : (i >= 2 - phase)

                    Image(
                        systemName: forward
                            ? "arrowtriangle.forward.fill"
                            : "arrowtriangle.backward.fill"
                    )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(isBright ? 1.0 : 0.3))
                }
            }
        } animation: { _ in
            .easeInOut(duration: 0.22)
        }
    }

    // MARK: - Drag Logic

    private func handleDragChanged(value: DragGesture.Value, in size: CGSize) {
        if !isDragging {
            // Determine drag type from initial gesture direction
            isDragging = true
            dragStartLocation = value.startLocation
            dragSeekTime = currentTime

            dragType = .horizontalSeek
            onSeekStarted()
        }

        switch dragType {
        case .horizontalSeek:
            // Map horizontal drag to time: full screen width = duration (capped at 5 min)
            let maxSeekRange = min(duration, 300)
            let fraction = value.translation.width / size.width
            let delta = TimeInterval(fraction) * maxSeekRange
            let newTime = max(0, min(duration, currentTime + delta))
            dragSeekTime = newTime
            onSeekChanged(newTime)
        default:
            break
        }
    }

    private func handleDragEnded(value: DragGesture.Value) {
        if dragType == .horizontalSeek {
            onSeekCommitted(dragSeekTime)
        }

        isDragging = false
        dragType = nil
        dragSeekTime = 0
    }

    // MARK: - Seek Indicator

    private var seekIndicator: some View {
        VStack(spacing: 4) {
            Text(TimeFormatting.playbackPosition(dragSeekTime))
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            let delta = dragSeekTime - currentTime
            Text(
                delta >= 0
                    ? "+\(TimeFormatting.playbackPosition(delta))"
                    : "-\(TimeFormatting.playbackPosition(abs(delta)))"
            )
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Vertical Indicators (Brightness / Volume)

    #if os(iOS)
        @ViewBuilder
        private func verticalIndicator(icon: String, value: CGFloat, maxValue: CGFloat) -> some View
        {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)

                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.3))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(
                                height: geo.size.height * min(max(value / maxValue, 0), 1)
                            )
                    }
                }
                .frame(width: 4, height: 100)
            }
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
            .environment(\.colorScheme, .dark)
        }

        private func brightnessIcon(for value: CGFloat) -> String {
            if value > 0.66 { return "sun.max.fill" }
            if value > 0.33 { return "sun.min.fill" }
            return "sun.min"
        }

        private func volumeIcon(for value: Float) -> String {
            if value <= 0 { return "speaker.slash.fill" }
            if value < 0.33 { return "speaker.wave.1.fill" }
            if value < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    #endif
}

// MARK: - Supporting Types

extension VideoGestureLayer {
    enum SkipSide: Equatable {
        case forward
        case backward
    }

    enum DragType {
        case horizontalSeek
        #if os(iOS)
            case verticalBrightness
            case verticalVolume
        #endif
    }
}

// MARK: - System Volume Helper (iOS)

#if os(iOS)
    import MediaPlayer

    /// Helper to get/set system volume without showing the system HUD.
    ///
    /// Uses `MPVolumeView` to access the volume slider, which bypasses the
    /// default system volume overlay.
    enum SystemVolumeHelper {
        private static var volumeView: MPVolumeView = {
            let view = MPVolumeView(frame: .zero)
            view.isHidden = true
            return view
        }()

        static func getVolume() -> Float {
            AVAudioSession.sharedInstance().outputVolume
        }

        @MainActor
        static func setVolume(_ volume: Float) {
            let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
            slider?.value = volume
        }
    }
#endif
