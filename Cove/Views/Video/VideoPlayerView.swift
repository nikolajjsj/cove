import AVKit
import Defaults
import JellyfinProvider
import MediaServerKit
import Models
import PlaybackEngine
import SwiftUI
import os

struct VideoPlayerView: View {
    let item: MediaItem
    let streamInfo: StreamInfo
    let startPosition: TimeInterval
    let mediaSegments: [MediaSegment]

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    @Default(.subtitleSize) private var subtitleSize
    @Default(.subtitleColor) private var subtitleColor
    @Default(.subtitleBackground) private var subtitleBackground

    private var coordinator: VideoPlayerCoordinator {
        appState.videoPlayerCoordinator
    }

    @State private var videoManager = VideoPlaybackManager()
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?

    // Tracks whether the video has actually started rendering frames.
    // Controls stay visible until this becomes true.
    @State private var hasStartedPlaying = false

    // Seeking (slider-driven)
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    // Gesture-driven seeking
    @State private var isGestureSeeking = false
    @State private var gestureSeekTime: TimeInterval = 0

    // Center-controls skip animation triggers
    @State private var forwardSkipTrigger: Int = 0
    @State private var backwardSkipTrigger: Int = 0
    @State private var showChapterList = false
    @State private var showSubtitleSearch = false

    // Landscape orientation
    #if os(iOS)
        @State private var previousOrientationMask: UIInterfaceOrientationMask?
    #endif

    var body: some View {
        ZStack {
            // Video rendering layer
            VideoRenderView(player: videoManager.player, videoGravity: videoManager.videoGravity)
                .ignoresSafeArea()

            #if os(tvOS)
                // tvOS: focus-driven controls overlay (Siri Remote)
                TVVideoControlsOverlay(
                    item: item,
                    videoManager: videoManager,
                    onDismiss: {
                        coordinator.dismiss()
                    }
                )
                .zIndex(3)
            #else
                // Gesture layer — reads currentTime in its own tracking scope
                GestureLayerContainer(
                    videoManager: videoManager,
                    skipForwardInterval: Defaults[.skipForwardInterval],
                    skipBackwardInterval: Defaults[.skipBackwardInterval],
                    onToggleControls: {
                        toggleControls()
                    },
                    onSkipForward: {
                        forwardSkipTrigger += 1
                        videoManager.skipForward(Defaults[.skipForwardInterval])
                        resetControlsTimer()
                    },
                    onSkipBackward: {
                        backwardSkipTrigger += 1
                        videoManager.skipBackward(Defaults[.skipBackwardInterval])
                        resetControlsTimer()
                    },
                    onSeekStarted: {
                        isGestureSeeking = true
                        gestureSeekTime = videoManager.currentTime
                        showControls = true
                        controlsTimer?.cancel()
                    },
                    onSeekChanged: { time in
                        gestureSeekTime = time
                    },
                    onSeekCommitted: { time in
                        videoManager.seek(to: time)
                        isGestureSeeking = false
                        resetControlsTimer()
                    },
                    onAspectRatioCycle: {
                        videoManager.cycleAspectRatio()
                    }
                )
                .zIndex(1)

                // Custom controls overlay — always in the tree for snappy toggling.
                // We animate opacity instead of inserting/removing the view.
                controlsOverlay
                    .opacity(showControls ? 1 : 0)
                    .allowsHitTesting(showControls)
                    .zIndex(3)
            #endif

            // Buffering / loading indicator (only when controls are hidden)
            if isLoadingVideo && !showControls {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .zIndex(2)
            }

            // External subtitle text overlay — reads currentSubtitleText in its own scope
            SubtitleOverlay(
                videoManager: videoManager,
                subtitleSize: subtitleSize,
                subtitleColor: subtitleColor,
                subtitleBackground: subtitleBackground
            )
            .zIndex(2.5)

            // Skip segment button — reads currentTime in its own scope
            SkipSegmentOverlay(
                mediaSegments: mediaSegments,
                videoManager: videoManager
            )
            .zIndex(3.5)

            // Next episode countdown
            if videoManager.showNextEpisodeCountdown, let next = videoManager.nextEpisode {
                NextEpisodeCountdownView(
                    next: next,
                    countdown: videoManager.nextEpisodeCountdown,
                    thumbnailURL: thumbnailURL(for: next),
                    onDismiss: { videoManager.dismissNextEpisodeCountdown() },
                    onPlayNow: { videoManager.playNextEpisode() }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(4)
            }
        }
        #if !os(tvOS)
            .animation(.easeOut(duration: 0.15), value: showControls)
        #endif
        .animation(.easeInOut(duration: 0.3), value: videoManager.showNextEpisodeCountdown)
        .background(Color.black)
        #if os(iOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        #endif
        .onAppear {
            applyLandscapeOrientation()
            setupAndPlay()
        }
        .onDisappear {
            controlsTimer?.cancel()
            videoManager.stop()
            // Belt-and-suspenders: also restore here in case the view is
            // removed without going through the dismiss button (e.g. PiP,
            // error dismissal, next-episode coordinator dismiss).
            restoreOrientation()
        }
        // Detect when media has actually started playing so we can auto-hide controls.
        .onChange(of: videoManager.isBuffering) { oldValue, newValue in
            if oldValue && !newValue && videoManager.isPlaying && !hasStartedPlaying {
                hasStartedPlaying = true
                scheduleControlsHide()
            }
        }
        .onChange(of: videoManager.isPlaying) { _, isPlaying in
            if isPlaying && !videoManager.isBuffering && !hasStartedPlaying {
                hasStartedPlaying = true
                scheduleControlsHide()
            }
        }
        .onChange(of: coordinator.isSwitchingQuality) { wasSwitching, isSwitching in
            // When a quality switch completes, reload the player with the new stream
            if wasSwitching && !isSwitching, let newInfo = coordinator.streamInfo {
                videoManager.loadAndPlay(
                    item: item,
                    streamInfo: newInfo,
                    startPosition: coordinator.startPosition
                )
            }
        }
        #if !os(tvOS)
            .sheet(isPresented: $showChapterList) {
                ChapterListSheet(
                    chapters: item.chapters,
                    currentTime: videoManager.currentTime,
                    duration: videoManager.duration,
                    itemId: item.id,
                    onSelectChapter: { chapter in
                        videoManager.seek(to: chapter.startPosition)
                        showChapterList = false
                        resetControlsTimer()
                    }
                )
                .environment(authManager)
                .presentationDetents([.medium, .large])
            }
        #endif
        .sheet(isPresented: $showSubtitleSearch) {
            SubtitleSearchSheet(
                viewModel: SubtitleSearchViewModel(
                    item: item,
                    streamInfo: streamInfo,
                    provider: authManager.provider,
                    videoManager: videoManager
                )
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Controls Overlay (iOS / macOS)

    #if !os(tvOS)
        @ViewBuilder
        private var controlsOverlay: some View {
            ZStack {
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

                    // Bottom: seek bar, time, subtitle/audio/speed/pip buttons
                    bottomBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Buffering / loading spinner shown over center controls
                if isLoadingVideo {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                        .allowsHitTesting(false)
                }
            }
        }
    #endif

    // MARK: - Top Bar

    #if !os(tvOS)
        private var topBar: some View {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    // Restore orientation eagerly — before the view starts its
                    // removal transition — so the device rotates back immediately.
                    restoreOrientation()
                    coordinator.dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
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

                    if let subtitle = topBarSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !item.chapters.isEmpty {
                    Button {
                        showChapterList = true
                        controlsTimer?.cancel()
                    } label: {
                        Label("Chapters", systemImage: "list.bullet.rectangle")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Aspect ratio toggle
                Button {
                    videoManager.cycleAspectRatio()
                } label: {
                    Label(
                        "Aspect Ratio",
                        systemImage: videoManager.videoGravity == .resizeAspectFill
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                #if os(iOS)
                    if videoManager.isPiPPossible {
                        Button {
                            videoManager.togglePiP()
                        } label: {
                            Label(
                                "Picture in Picture",
                                systemImage: videoManager.isPiPActive ? "pip.exit" : "pip.enter"
                            )
                            .labelStyle(.iconOnly)
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

        /// Subtitle text for the top bar — shows series info for episodes.
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
    #endif

    // MARK: - Center Controls

    #if !os(tvOS)
        private var centerControls: some View {
            HStack(spacing: 48) {
                Button {
                    backwardSkipTrigger += 1
                    videoManager.skipBackward(Defaults[.skipBackwardInterval])
                    resetControlsTimer()
                } label: {
                    Label("Skip Back", systemImage: skipBackwardIcon)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: backwardSkipTrigger)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    videoManager.togglePlayPause()
                    resetControlsTimer()
                } label: {
                    Label(
                        videoManager.isPlaying ? "Pause" : "Play",
                        systemImage: videoManager.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    forwardSkipTrigger += 1
                    videoManager.skipForward(Defaults[.skipForwardInterval])
                    resetControlsTimer()
                } label: {
                    Label("Skip Forward", systemImage: skipForwardIcon)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: forwardSkipTrigger)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if videoManager.nextEpisode != nil && !videoManager.showNextEpisodeCountdown {
                    Button("Next Episode", systemImage: "forward.end.fill") {
                        videoManager.playNextEpisode()
                        resetControlsTimer()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
        }

        private var skipBackwardIcon: String {
            let interval = Int(Defaults[.skipBackwardInterval])
            return "gobackward.\(interval)"
        }

        private var skipForwardIcon: String {
            let interval = Int(Defaults[.skipForwardInterval])
            return "goforward.\(interval)"
        }
    #endif

    // MARK: - Bottom Bar

    #if !os(tvOS)

        /// The bottom bar composes time-dependent children (slider, labels) and
        /// time-independent children (menus) as separate `View` structs so that
        /// rapid `currentTime` ticks don't cause menu re-renders.
        private var bottomBar: some View {
            VStack(spacing: 8) {
                PlayerSeekSlider(
                    videoManager: videoManager,
                    isSeeking: $isSeeking,
                    seekTime: $seekTime,
                    isGestureSeeking: isGestureSeeking,
                    gestureSeekTime: gestureSeekTime
                )

                HStack(spacing: 12) {
                    PlayerTimeLabels(
                        videoManager: videoManager,
                        isSeeking: isSeeking,
                        seekTime: seekTime,
                        isGestureSeeking: isGestureSeeking,
                        gestureSeekTime: gestureSeekTime
                    )

                    Spacer()

                    PlayerMenuBar(
                        item: item,
                        streamInfo: streamInfo,
                        videoManager: videoManager,
                        coordinator: coordinator,
                        authManager: authManager,
                        showSubtitleSearch: $showSubtitleSearch,
                        onControlsInteraction: StableAction(resetControlsTimer)
                    )
                }
            }
        }

    #endif

    /// Whether the video is in a loading state — either actively buffering
    /// or still waiting for the player item to report its duration.
    private var isLoadingVideo: Bool {
        videoManager.isBuffering
            || (videoManager.currentItem != nil && videoManager.duration <= 0)
    }

    // MARK: - Setup

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "VideoPlayer")

    private func setupAndPlay() {
        // Debug: log media segments received from the coordinator
        logger.info("Setting up playback for \(self.item.title) (id: \(self.item.id.rawValue))")
        logger.info("Media segments received: \(self.mediaSegments.count)")
        for segment in mediaSegments {
            logger.info(
                "  Segment: type=\(segment.type.rawValue) start=\(segment.startTime) end=\(segment.endTime)"
            )
        }

        // Restore persisted playback speed
        let savedSpeed = Defaults[.videoPlaybackSpeed]
        if savedSpeed != 1.0 {
            videoManager.setSpeed(savedSpeed)
        }

        // Wire playback reporting callbacks
        let provider = authManager.provider
        let coordinator = self.coordinator

        // Provide artwork URL for lock screen / Control Center NowPlaying info
        videoManager.artworkURLProvider = { item in
            provider.imageURL(
                for: item,
                type: .primary,
                maxSize: CGSize(width: 600, height: 340)
            )
        }

        videoManager.onPlaybackStart = { item, position in
            try? await provider.reportPlaybackStart(item: item, position: position)
        }
        videoManager.onPlaybackProgress = { item, position in
            try? await provider.reportPlaybackProgress(item: item, position: position)
        }
        videoManager.onPlaybackStopped = { [appState] item, position in
            try? await provider.reportPlaybackStopped(item: item, position: position)
            appState.userDataStore?.updatePlaybackPosition(
                itemId: item.id,
                position: position,
                runtime: item.runtime,
                currentData: item.userData
            )
        }
        videoManager.onPlayNextEpisode = { [self] nextItem in
            let provider = authManager.provider
            let vm = videoManager

            // Reset view-level state immediately so the UI doesn't show
            // stale seeking/progress values from the previous episode
            hasStartedPlaying = false
            isSeeking = false
            seekTime = 0
            isGestureSeeking = false
            gestureSeekTime = 0
            showControls = true
            controlsTimer?.cancel()

            Task {
                await coordinator.transitionToNextEpisode(nextItem, using: provider)

                // Reload the player with the new stream
                if let newStream = coordinator.streamInfo,
                    let newItem = coordinator.currentItem
                {
                    vm.loadAndPlay(
                        item: newItem,
                        streamInfo: newStream,
                        startPosition: coordinator.startPosition
                    )

                    // Fetch the next-next episode
                    if newItem.mediaType == .episode,
                        Defaults[.autoPlayNextEpisode]
                    {
                        let next = try? await provider.nextEpisodeAfter(item: newItem)
                        vm.setNextEpisode(next)
                    }
                }
            }
        }
        videoManager.onPlaybackError = { item, error in
            coordinator.error = VideoPlayerCoordinator.PlaybackError(
                itemTitle: item.title,
                underlyingError: error
            )
            coordinator.dismiss()
        }

        videoManager.loadAndPlay(
            item: item,
            streamInfo: streamInfo,
            startPosition: startPosition
        )

        // Fetch next episode for auto-play
        if item.mediaType == .episode,
            Defaults[.autoPlayNextEpisode]
        {
            let provider = authManager.provider
            Task {
                let next = try? await provider.nextEpisodeAfter(item: item)
                videoManager.setNextEpisode(next)
            }
        }

        // Don't schedule auto-hide yet — controls stay visible until
        // playback has actually started (detected via onChange handlers).
        // For instant-start local files where isBuffering is never true,
        // the isPlaying onChange will catch it immediately.
    }

    // MARK: - Controls Visibility

    #if !os(tvOS)
        private func toggleControls() {
            showControls.toggle()
            if showControls {
                scheduleControlsHide()
            } else {
                controlsTimer?.cancel()
            }
        }

        private func resetControlsTimer() {
            showControls = true
            scheduleControlsHide()
        }
    #endif

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                showControls = false
            }
        }
    }

    // MARK: - Orientation Management

    private func applyLandscapeOrientation() {
        #if os(iOS)
            guard Defaults[.forceLandscapeVideo] else { return }

            // Store current orientation mask and force landscape
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
            {
                previousOrientationMask =
                    windowScene.windows.first?.windowScene?.effectiveGeometry
                        .interfaceOrientation == .portrait ? .portrait : nil
            }

            // Request landscape orientation
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
            {
                let preferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: .landscape)
                windowScene.requestGeometryUpdate(preferences) { error in
                    // Best effort — some devices or multitasking modes may not support this
                }
            }

            // Also set the supported orientations via the app delegate approach
            UIViewController.attemptRotationToDeviceOrientation()
        #endif
    }

    private func restoreOrientation() {
        #if os(iOS)
            guard Defaults[.forceLandscapeVideo] else { return }

            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
            {
                // Actively request portrait so the device rotates back
                // immediately instead of just "allowing" all orientations
                // (which leaves the device stuck in landscape).
                let portraitPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: .portrait)
                windowScene.requestGeometryUpdate(portraitPreferences) { _ in }

                // After a short delay, re-allow all orientations so the user
                // can freely rotate again (e.g. landscape for another video).
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    let allPreferences = UIWindowScene.GeometryPreferences.iOS(
                        interfaceOrientations: .all)
                    windowScene.requestGeometryUpdate(allPreferences) { _ in }
                }
            }

            UIViewController.attemptRotationToDeviceOrientation()
        #endif
    }

    // MARK: - Helpers

    private func thumbnailURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
    }
}

// MARK: - Stable Action Wrapper

/// A callback wrapper that prevents closures from causing SwiftUI view invalidation.
///
/// Closures can't be compared for equality, so passing them directly as view
/// parameters causes SwiftUI to re-render the child view on every parent evaluation.
/// This wrapper always compares as equal, telling SwiftUI the callback hasn't changed.
private struct StableAction: Equatable {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    func callAsFunction() {
        perform()
    }

    static func == (lhs: StableAction, rhs: StableAction) -> Bool {
        true  // Closures can't be compared; treat as always equal to prevent re-renders
    }
}

// MARK: - Gesture Layer Container

/// Wraps `VideoGestureLayer` so that reads of `videoManager.currentTime` and
/// `videoManager.duration` happen in this child view's `@Observable` tracking
/// scope rather than in `VideoPlayerView.body`.
#if !os(tvOS)
    private struct GestureLayerContainer: View {
        let videoManager: VideoPlaybackManager
        let skipForwardInterval: TimeInterval
        let skipBackwardInterval: TimeInterval
        let onToggleControls: () -> Void
        let onSkipForward: () -> Void
        let onSkipBackward: () -> Void
        let onSeekStarted: () -> Void
        let onSeekChanged: (TimeInterval) -> Void
        let onSeekCommitted: (TimeInterval) -> Void
        let onAspectRatioCycle: () -> Void

        var body: some View {
            VideoGestureLayer(
                currentTime: videoManager.currentTime,
                duration: videoManager.duration,
                skipForwardInterval: skipForwardInterval,
                skipBackwardInterval: skipBackwardInterval,
                onToggleControls: onToggleControls,
                onSkipForward: onSkipForward,
                onSkipBackward: onSkipBackward,
                onSeekStarted: onSeekStarted,
                onSeekChanged: onSeekChanged,
                onSeekCommitted: onSeekCommitted,
                onAspectRatioCycle: onAspectRatioCycle
            )
        }
    }
#endif

// MARK: - Subtitle Overlay

/// Reads `videoManager.currentSubtitleText` in its own `@Observable` tracking
/// scope so that subtitle text changes don't invalidate `VideoPlayerView.body`.
private struct SubtitleOverlay: View {
    let videoManager: VideoPlaybackManager
    let subtitleSize: SubtitleSize
    let subtitleColor: SubtitleColor
    let subtitleBackground: SubtitleBackground

    var body: some View {
        if let subtitleText = videoManager.currentSubtitleText {
            VStack {
                Spacer()
                SubtitleTextView(
                    text: subtitleText,
                    size: subtitleSize,
                    color: subtitleColor,
                    background: subtitleBackground
                )
                .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Skip Segment Overlay

/// Reads `videoManager.currentTime` in its own tracking scope to compute the
/// active skippable segment without triggering `VideoPlayerView.body` re-evaluation.
private struct SkipSegmentOverlay: View {
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

// MARK: - Player Seek Slider

/// The seek slider, isolated into its own view so that `videoManager.currentTime`
/// reads happen here instead of in `VideoPlayerView.body`.
#if !os(tvOS)
    private struct PlayerSeekSlider: View {
        let videoManager: VideoPlaybackManager
        @Binding var isSeeking: Bool
        @Binding var seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval

        private var displayTime: TimeInterval {
            if isGestureSeeking { return gestureSeekTime }
            if isSeeking { return seekTime }
            return videoManager.currentTime
        }

        var body: some View {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { newValue in
                        if !isSeeking {
                            isSeeking = true
                        }
                        seekTime = newValue
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
    }
#endif

// MARK: - Player Time Labels

/// Displays elapsed / total time, isolated so `currentTime` reads don't
/// propagate up to `VideoPlayerView.body`.
#if !os(tvOS)
    private struct PlayerTimeLabels: View {
        let videoManager: VideoPlaybackManager
        let isSeeking: Bool
        let seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval

        private var displayTime: TimeInterval {
            if isGestureSeeking { return gestureSeekTime }
            if isSeeking { return seekTime }
            return videoManager.currentTime
        }

        var body: some View {
            HStack(spacing: 12) {
                Text(TimeFormatting.playbackPosition(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(TimeFormatting.playbackPosition(videoManager.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
#endif

// MARK: - Player Menu Bar

#if !os(tvOS)

    /// Extracted menu bar for the video player controls.
    ///
    /// This is a separate `View` struct (not a computed property on `VideoPlayerView`)
    /// so that it gets its own `@Observable` tracking scope. This prevents the menus
    /// from re-rendering every time `videoManager.currentTime` changes (~10×/sec),
    /// which caused visible flickering/flashing of menu buttons and dismissed open menus.
    ///
    /// The `onControlsInteraction` callback uses `StableAction` (always-equal wrapper)
    /// so that closure identity changes don't cause SwiftUI to treat this view as modified.
    private struct PlayerMenuBar: View {
        let item: MediaItem
        let streamInfo: StreamInfo
        let videoManager: VideoPlaybackManager
        let coordinator: VideoPlayerCoordinator
        let authManager: AuthManager
        @Binding var showSubtitleSearch: Bool
        let onControlsInteraction: StableAction

        var body: some View {
            HStack(spacing: 12) {
                // Quality picker
                if coordinator.availableQualities.count > 1 {
                    qualityMenu
                }

                // Speed picker
                speedMenu

                // Audio track picker
                if videoManager.audioTracks.count > 1 {
                    audioTrackMenu
                }

                // Subtitle picker
                subtitleMenu

                // AirPlay
                #if os(iOS)
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                        .tint(.white)
                #endif
            }
        }

        // MARK: - Quality Menu

        private var qualityMenu: some View {
            Menu {
                Picker(
                    "Quality",
                    selection: Binding(
                        get: { coordinator.activeQuality },
                        set: { newQuality in
                            coordinator.switchQuality(
                                to: newQuality,
                                currentTime: videoManager.currentTime
                            )
                            onControlsInteraction()
                        }
                    )
                ) {
                    ForEach(coordinator.availableQualities, id: \.self) { quality in
                        Text(qualityLabel(for: quality)).tag(quality)
                    }
                }
            } label: {
                Image(systemName: coordinator.activeQuality == .auto ? "dial.low" : "dial.high")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        coordinator.activeQuality == .auto ? .white : Color.accentColor
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }

        private func qualityLabel(for quality: StreamingQuality) -> String {
            if quality == .auto, let height = coordinator.sourceVideoHeight {
                let resolution = height >= 2160 ? "4K" : "\(height)p"
                if let bitrate = coordinator.sourceVideoBitrate {
                    let mbps = (Double(bitrate) / 1_000_000).formatted(
                        .number.precision(.fractionLength(0)))
                    return "Auto (\(resolution) · \(mbps) Mbps)"
                }
                return "Auto (\(resolution))"
            }
            return quality.label
        }

        // MARK: - Speed Menu

        private var speedMenu: some View {
            Menu {
                Picker(
                    "Playback Speed",
                    selection: Binding(
                        get: { videoManager.playbackSpeed },
                        set: { newSpeed in
                            videoManager.setSpeed(newSpeed)
                            Defaults[.videoPlaybackSpeed] = newSpeed
                            onControlsInteraction()
                        }
                    )
                ) {
                    ForEach(VideoPlaybackManager.speedOptions, id: \.self) { speed in
                        Text(speedDisplayText(speed) + (speed == 1.0 ? " (Normal)" : ""))
                            .tag(speed)
                    }
                }
            } label: {
                Text(speedLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        videoManager.playbackSpeed != 1.0 ? Color.accentColor : .white
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }

        private var speedLabel: String {
            let speed = videoManager.playbackSpeed
            if speed == Float(Int(speed)) {
                return "\(Int(speed))×"
            }
            return "\(speed.formatted(.number.precision(.fractionLength(1))))×"
        }

        private func speedDisplayText(_ speed: Float) -> String {
            if speed == Float(Int(speed)) {
                return "\(Int(speed))×"
            }
            return "\(speed.formatted(.number.precision(.significantDigits(2))))×"
        }

        // MARK: - Subtitle Menu

        private var subtitleMenu: some View {
            Menu {
                Picker(
                    "Subtitles",
                    selection: Binding(
                        get: { videoManager.selectedSubtitleIndex ?? -1 },
                        set: { newIndex in
                            let index = newIndex == -1 ? nil : newIndex
                            let url: URL? = {
                                guard let idx = index,
                                    let sourceId = streamInfo.mediaSourceId
                                else { return nil }
                                return authManager.provider.subtitleURL(
                                    itemId: item.id,
                                    mediaSourceId: sourceId,
                                    subtitleIndex: idx
                                )
                            }()
                            videoManager.selectSubtitle(at: index, externalURL: url)
                            onControlsInteraction()
                        }
                    )
                ) {
                    Text("Off").tag(-1)

                    ForEach(videoManager.subtitleTracks) { track in
                        subtitleTrackLabel(for: track)
                            .tag(track.id)
                    }
                }

                Divider()

                Button("Search Online…", systemImage: "magnifyingglass") {
                    showSubtitleSearch = true
                }
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
        }

        @ViewBuilder
        private func subtitleTrackLabel(for track: SubtitleTrack) -> some View {
            if let language = track.language,
                let localized = Locale.current.localizedString(forLanguageCode: language)
            {
                Text("\(track.title) — \(localized)")
            } else {
                Text(track.title)
            }
        }

        // MARK: - Audio Track Menu

        private var audioTrackMenu: some View {
            Menu {
                Picker(
                    "Audio Track",
                    selection: Binding(
                        get: { videoManager.selectedAudioTrackIndex ?? 0 },
                        set: { newIndex in
                            videoManager.selectAudioTrack(at: newIndex)
                            onControlsInteraction()
                        }
                    )
                ) {
                    ForEach(videoManager.audioTracks) { track in
                        audioTrackLabel(for: track)
                            .tag(track.id)
                    }
                }
            } label: {
                Image(systemName: "waveform.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }

        @ViewBuilder
        private func audioTrackLabel(for track: AudioTrack) -> some View {
            if let language = track.language,
                let localized = Locale.current.localizedString(forLanguageCode: language)
            {
                Text("\(track.title) — \(localized)" + (track.isDefault ? " (Default)" : ""))
            } else {
                Text(track.title + (track.isDefault ? " (Default)" : ""))
            }
        }
    }

#endif

// MARK: - Skip Segment Button

/// A floating "Skip Intro" / "Skip Credits" button that appears when playback
/// enters a skippable media segment.
private struct SkipSegmentButton: View {
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

// MARK: - Next Episode Countdown

/// A floating card shown near the end of an episode, counting down to
/// auto-play of the next episode. Provides dismiss and "Play Now" actions.
private struct NextEpisodeCountdownView: View {
    let next: MediaItem
    let countdown: Int
    let thumbnailURL: URL?
    let onDismiss: () -> Void
    let onPlayNow: () -> Void

    var body: some View {
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
                            onDismiss()
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        MediaImage.videoThumbnail(url: thumbnailURL, cornerRadius: 6)
                            .frame(width: 100)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text("Starting in \(countdown)s")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .monospacedDigit()
                        }
                    }

                    Button {
                        onPlayNow()
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
                .background(
                    .ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)
                )
                .environment(\.colorScheme, .dark)
            }
            .padding(24)
        }
    }
}
