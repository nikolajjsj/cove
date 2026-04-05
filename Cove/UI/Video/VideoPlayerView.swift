import AVKit
import ImageService
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

struct VideoPlayerView: View {
    let item: MediaItem
    let streamInfo: StreamInfo
    let startPosition: TimeInterval

    @Environment(AppState.self) private var appState

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    @State private var videoManager = VideoPlaybackManager()
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var showSubtitlePicker = false

    // Seeking
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    var body: some View {
        ZStack {
            // Video rendering layer
            VideoRenderView(player: videoManager.player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControls()
                }

            // Buffering indicator
            if videoManager.isBuffering {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Custom controls overlay
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }

            // Next episode countdown
            if videoManager.showNextEpisodeCountdown, let next = videoManager.nextEpisode {
                nextEpisodeCountdownView(next: next)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: videoManager.showNextEpisodeCountdown)
        .background(Color.black)
        #if os(iOS)
            .statusBarHidden(!showControls)
            .persistentSystemOverlays(showControls ? .automatic : .hidden)
        #endif
        .onAppear {
            setupAndPlay()
        }
        .onDisappear {
            controlsTimer?.cancel()
            videoManager.stop()
        }
        .sheet(isPresented: $showSubtitlePicker) {
            subtitlePickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Controls Overlay

    @ViewBuilder
    private var controlsOverlay: some View {
        ZStack {
            // Tap-to-dismiss layer — sits behind all interactive controls.
            // Using Color.clear + contentShape so it fills the screen but
            // doesn't block buttons/sliders that are placed on top of it.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControls()
                }

            // Gradient backgrounds (top and bottom) — purely decorative
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar: dismiss, title, settings
                topBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()
                
                // Center: skip back, play/pause, skip forward
                centerControls
                
                Spacer()
                
                // Bottom: seek bar, time, subtitle/pip buttons
                bottomBar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                coordinator.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = videoManager.currentItem?.overview {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            #if os(iOS)
                if videoManager.isPiPPossible {
                    Button {
                        videoManager.togglePiP()
                    } label: {
                        Image(systemName: videoManager.isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            #endif
        }
    }

    // MARK: - Center Controls

    private var centerControls: some View {
        HStack(spacing: 48) {
            Button {
                videoManager.skipBackward()
                resetControlsTimer()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                videoManager.togglePlayPause()
                resetControlsTimer()
            } label: {
                Image(systemName: videoManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                videoManager.skipForward()
                resetControlsTimer()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            seekSlider

            HStack(spacing: 16) {
                // Time labels
                Text(formatTime(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(formatTime(videoManager.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // Subtitle button
                if !videoManager.subtitleTracks.isEmpty {
                    Button {
                        showSubtitlePicker = true
                    } label: {
                        Image(
                            systemName: videoManager.selectedSubtitleIndex != nil
                                ? "captions.bubble.fill" : "captions.bubble"
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Airplay
                #if os(iOS)
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                        .tint(.white)
                #endif
            }
        }
    }

    // MARK: - Seek Slider

    private var displayTime: TimeInterval {
        isSeeking ? seekTime : videoManager.currentTime
    }

    private var seekSlider: some View {
        Slider(
            value: Binding(
                get: { displayTime },
                set: { newValue in
                    if !isSeeking {
                        isSeeking = true
                    }
                    seekTime = newValue
                    resetControlsTimer()
                }
            ),
            in: 0...max(videoManager.duration, 1),
            onEditingChanged: { editing in
                if !editing {
                    videoManager.seek(to: seekTime)
                    isSeeking = false
                }
            }
        )
        .tint(.white)
    }

    // MARK: - Subtitle Picker Sheet

    @ViewBuilder
    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                Button {
                    videoManager.selectedSubtitleIndex = nil
                    showSubtitlePicker = false
                } label: {
                    HStack {
                        Text("Off")
                            .foregroundStyle(.primary)
                        Spacer()
                        if videoManager.selectedSubtitleIndex == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Subtitles")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSubtitlePicker = false
                    }
                }
            }
        }
    }

    // MARK: - Next Episode Countdown

    @ViewBuilder
    private func nextEpisodeCountdownView(next: MediaItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Up Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)

                        Spacer()

                        Button {
                            //                            videoManager.showNextEpisodeCountdown = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        // Next episode thumbnail
                        LazyImage(url: thumbnailURL(for: next)) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                            } else {
                                Rectangle()
                                    .fill(.white.opacity(0.1))
                                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                                    .overlay {
                                        Image(systemName: "play.rectangle")
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                            }
                        }
                        .frame(width: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text("Starting in \(videoManager.nextEpisodeCountdown)s")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .monospacedDigit()
                        }
                    }

                    Button {
                        videoManager.playNextEpisode()
                    } label: {
                        Text("Play Now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(width: 280)
                .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                .environment(\.colorScheme, .dark)
            }
            .padding(24)
        }
    }

    // MARK: - Setup

    private func setupAndPlay() {
        // Wire playback reporting callbacks
        nonisolated(unsafe) let provider = appState.provider
        let coordinator = self.coordinator

        videoManager.onPlaybackStart = { item, position in
            try? await provider.reportPlaybackStart(item: item, position: position)
        }
        videoManager.onPlaybackProgress = { item, position in
            try? await provider.reportPlaybackProgress(item: item, position: position)
        }
        videoManager.onPlaybackStopped = { item, position in
            try? await provider.reportPlaybackStopped(item: item, position: position)
        }
        videoManager.onPlayNextEpisode = { _ in
            // Dismiss and let the parent handle navigation to the next episode
            coordinator.dismiss()
        }

        videoManager.loadAndPlay(
            item: item,
            streamInfo: streamInfo,
            startPosition: startPosition
        )
        scheduleControlsHide()
    }

    // MARK: - Controls Visibility

    private func toggleControls() {
        showControls.toggle()
        if showControls {
            scheduleControlsHide()
        } else {
            controlsTimer?.cancel()
        }
    }

    private func resetControlsTimer() {
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                showControls = false
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", mins)):\(String(format: "%02d", secs))"
        } else {
            return "\(mins):\(String(format: "%02d", secs))"
        }
    }

    private func thumbnailURL(for item: MediaItem) -> URL? {
        appState.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
    }
}

// MARK: - AirPlay Button (iOS)

#if os(iOS)
    private struct AirPlayButton: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let routePicker = AVRoutePickerView()
            routePicker.tintColor = .white
            routePicker.activeTintColor = .systemBlue
            routePicker.prioritizesVideoDevices = true
            return routePicker
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }
#endif
