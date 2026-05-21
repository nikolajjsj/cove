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

    // Tracks the window scene geometry we unlocked on entry so we can always restore it on exit.
    #if os(iOS)
        @State private var didUnlockOrientation = false
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
                VideoControlsOverlay(
                    item: item,
                    streamInfo: streamInfo,
                    videoManager: videoManager,
                    coordinator: coordinator,
                    authManager: authManager,
                    isLoadingVideo: isLoadingVideo,
                    isSeeking: $isSeeking,
                    seekTime: $seekTime,
                    isGestureSeeking: isGestureSeeking,
                    gestureSeekTime: gestureSeekTime,
                    backwardSkipTrigger: $backwardSkipTrigger,
                    forwardSkipTrigger: $forwardSkipTrigger,
                    showChapterList: $showChapterList,
                    showSubtitleSearch: $showSubtitleSearch,
                    onDismiss: {
                        restoreOrientation()
                        coordinator.dismiss()
                    },
                    onResetTimer: resetControlsTimer,
                    onCancelTimer: { controlsTimer?.cancel() }
                )
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
            configureOrientationForPlayback()
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
            if isPlaying {
                // Mark first play and schedule auto-hide.
                if !videoManager.isBuffering && !hasStartedPlaying {
                    hasStartedPlaying = true
                }
                scheduleControlsHide()
            } else {
                // Paused or stopped: cancel any pending hide and keep controls visible.
                controlsTimer?.cancel()
                showControls = true
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
                // Only auto-hide when actively playing; keep controls visible when paused.
                if videoManager.isPlaying {
                    scheduleControlsHide()
                }
            } else {
                controlsTimer?.cancel()
            }
        }

        private func resetControlsTimer() {
            showControls = true
            // Only schedule auto-hide while playing.
            if videoManager.isPlaying {
                scheduleControlsHide()
            } else {
                controlsTimer?.cancel()
            }
        }
    #endif

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(4))
            // Double-check playback state at hide time; user may have paused during the delay.
            if !Task.isCancelled && videoManager.isPlaying {
                showControls = false
            }
        }
    }

    // MARK: - Orientation Management

    /// Unlocks the window to support both portrait and landscape during playback.
    ///
    /// If the user has "Force landscape" enabled the device is first rotated into
    /// landscape, then unlocked — so it starts sideways but can still be freely
    /// rotated afterwards. Without the setting we unlock immediately.
    ///
    /// Because `requestGeometryUpdate(.all)` tells the system all orientations are
    /// supported, iOS/SwiftUI automatically re-layouts the view tree whenever the
    /// device physically rotates — no `NotificationCenter` observer is needed.
    private func configureOrientationForPlayback() {
        #if os(iOS)
            if Defaults[.forceLandscapeVideo] {
                // Snap to landscape first so the user's preference is honoured,
                // then unlock so the device can freely follow physical rotation.
                requestOrientationUpdate(.landscape)
                Task { @MainActor in
                    // Give the initial landscape rotation a moment to settle.
                    try? await Task.sleep(for: .milliseconds(350))
                    requestOrientationUpdate(.all)
                }
            } else {
                // Immediately allow both portrait and landscape.
                requestOrientationUpdate(.all)
            }
            didUnlockOrientation = true
        #endif
    }

    /// Restores the window to portrait and then re-allows all orientations so the
    /// rest of the app is not left in a non-portrait locked state.
    private func restoreOrientation() {
        #if os(iOS)
            guard didUnlockOrientation else { return }
            didUnlockOrientation = false

            // Actively request portrait so the device snaps back immediately
            // rather than waiting for the user to physically rotate.
            requestOrientationUpdate(.portrait)

            // Re-allow all orientations after the portrait transition settles,
            // so the rest of the app can still rotate if it needs to.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                requestOrientationUpdate(.all)
            }
        #endif
    }

    /// Sends a geometry-update request to the key window scene.
    /// Best-effort: silently ignores failures (e.g. multitasking or Split View).
    #if os(iOS)
        private func requestOrientationUpdate(_ orientations: UIInterfaceOrientationMask) {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first
            else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: orientations)
            windowScene.requestGeometryUpdate(preferences) { _ in }
        }
    #endif

    // MARK: - Helpers

    private func thumbnailURL(for item: MediaItem) -> URL? {
        authManager.provider.imageURL(
            for: item,
            type: .primary,
            maxSize: CGSize(width: 320, height: 180)
        )
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
