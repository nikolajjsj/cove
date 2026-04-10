#if os(tvOS)
    import Defaults
    import Models
    import PlaybackEngine
    import SwiftUI

    /// Focus-driven video player controls for tvOS and the Siri Remote.
    ///
    /// On tvOS, the standard interaction model is:
    /// - **Click** the trackpad to show/hide controls
    /// - **Swipe** left/right to scrub (handled by the `onMoveCommand`)
    /// - **Play/Pause** button on the remote (handled by `MPRemoteCommandCenter`)
    /// - **Menu** button to dismiss
    ///
    /// Controls auto-hide after 5 seconds of inactivity, matching the Apple TV system player.
    struct TVVideoControlsOverlay: View {
        let item: MediaItem
        @Bindable var videoManager: VideoPlaybackManager
        let onDismiss: () -> Void

        @State private var showControls = true
        @State private var controlsTimer: Task<Void, Never>?

        // Seeking
        @State private var isSeeking = false
        @State private var seekTime: TimeInterval = 0

        var body: some View {
            ZStack {
                // Tap to toggle controls
                Color.clear
                    .focusable()
                    .onPlayPauseCommand {
                        videoManager.togglePlayPause()
                        showControls = true
                        scheduleControlsHide()
                    }
                    .onExitCommand {
                        if showControls {
                            showControls = false
                        } else {
                            onDismiss()
                        }
                    }
                    .onMoveCommand { direction in
                        showControls = true
                        scheduleControlsHide()
                        handleMoveCommand(direction)
                    }
                    .onSelectCommand {
                        toggleControls()
                    }

                // Controls
                if showControls {
                    controlsContent
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
            .onAppear {
                scheduleControlsHide()
            }
            .onDisappear {
                controlsTimer?.cancel()
            }
        }

        // MARK: - Controls Content

        private var controlsContent: some View {
            ZStack {
                // Gradient scrim
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Top bar
                    topBar
                        .padding(.horizontal, 48)
                        .padding(.top, 32)

                    Spacer()

                    // Center transport controls
                    transportControls

                    Spacer()

                    // Bottom bar with progress
                    bottomBar
                        .padding(.horizontal, 48)
                        .padding(.bottom, 32)
                }
            }
        }

        // MARK: - Top Bar

        private var topBar: some View {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = topBarSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("Close", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
        }

        private var topBarSubtitle: String? {
            if item.mediaType == .episode {
                var parts: [String] = []
                if let s = item.parentIndexNumber, let e = item.indexNumber {
                    parts.append("S\(s) E\(e)")
                }
                if let series = item.seriesName {
                    parts.append(series)
                }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
            return item.productionYear.map { String($0) }
        }

        // MARK: - Transport Controls

        private var transportControls: some View {
            HStack(spacing: 60) {
                Button {
                    videoManager.skipBackward(Defaults[.skipBackwardInterval])
                    scheduleControlsHide()
                } label: {
                    Label(
                        "Skip Back",
                        systemImage: "gobackward.\(Int(Defaults[.skipBackwardInterval]))"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .contentShape(.rect)
                }

                Button {
                    videoManager.togglePlayPause()
                    scheduleControlsHide()
                } label: {
                    Label(
                        videoManager.isPlaying ? "Pause" : "Play",
                        systemImage: videoManager.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 100, height: 100)
                    .contentShape(.rect)
                }

                Button {
                    videoManager.skipForward(Defaults[.skipForwardInterval])
                    scheduleControlsHide()
                } label: {
                    Label(
                        "Skip Forward",
                        systemImage: "goforward.\(Int(Defaults[.skipForwardInterval]))"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .contentShape(.rect)
                }
            }
        }

        // MARK: - Bottom Bar

        private var bottomBar: some View {
            VStack(spacing: 12) {
                // Progress bar
                ProgressView(value: displayTime, total: max(videoManager.duration, 1))
                    .tint(.white)

                HStack {
                    Text(TimeFormatting.playbackPosition(displayTime))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    // Speed indicator (if not 1x)
                    if videoManager.playbackSpeed != 1.0 {
                        Text(
                            "\(videoManager.playbackSpeed, format: .number.precision(.fractionLength(1)))×"
                        )
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(.white.opacity(0.8))
                    }

                    Text(TimeFormatting.playbackPosition(videoManager.duration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }

        private var displayTime: TimeInterval {
            isSeeking ? seekTime : videoManager.currentTime
        }

        // MARK: - Input Handling

        private func handleMoveCommand(_ direction: MoveCommandDirection) {
            let skipInterval: TimeInterval = 10
            switch direction {
            case .left:
                videoManager.skipBackward(skipInterval)
            case .right:
                videoManager.skipForward(skipInterval)
            default:
                break
            }
        }

        private func toggleControls() {
            showControls.toggle()
            if showControls {
                scheduleControlsHide()
            } else {
                controlsTimer?.cancel()
            }
        }

        private func scheduleControlsHide() {
            controlsTimer?.cancel()
            controlsTimer = Task {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    showControls = false
                }
            }
        }
    }
#endif
