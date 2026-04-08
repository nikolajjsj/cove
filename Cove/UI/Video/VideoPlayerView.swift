import AVKit
import Defaults
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

struct VideoPlayerView: View {
    let item: MediaItem
    let streamInfo: StreamInfo
    let startPosition: TimeInterval
    let mediaSegments: [MediaSegment]

    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

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

    // Landscape orientation
    #if os(iOS)
        @State private var previousOrientationMask: UIInterfaceOrientationMask?
    #endif

    var body: some View {
        ZStack {
            // Video rendering layer
            VideoRenderView(player: videoManager.player, videoGravity: videoManager.videoGravity)
                .ignoresSafeArea()

            // Gesture layer — always active underneath controls
            VideoGestureLayer(
                currentTime: videoManager.currentTime,
                duration: videoManager.duration,
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

            // Buffering indicator (only when controls are hidden)
            if videoManager.isBuffering && !showControls {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .zIndex(2)
            }

            // External subtitle text overlay
            if let subtitleText = videoManager.currentSubtitleText {
                VStack {
                    Spacer()
                    subtitleLabel(subtitleText).padding(.bottom, 12)
                }
                .allowsHitTesting(false)
                .zIndex(2.5)
            }

            // Skip segment button (intro, credits, recap)
            skipSegmentButton
                .zIndex(2.8)

            // Custom controls overlay — always in the tree for snappy toggling.
            // We animate opacity instead of inserting/removing the view.
            controlsOverlay
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .zIndex(3)

            // Next episode countdown
            if videoManager.showNextEpisodeCountdown, let next = videoManager.nextEpisode {
                nextEpisodeCountdownView(next: next)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showControls)
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

    }

    // MARK: - Controls Overlay

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

            // Buffering spinner shown over center controls
            if videoManager.isBuffering {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Top Bar

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

    // MARK: - Center Controls

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

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            seekSlider

            HStack(spacing: 12) {
                // Time labels
                Text(TimeFormatting.playbackPosition(displayTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(TimeFormatting.playbackPosition(videoManager.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // Quality picker
                if coordinator.availableQualities.count > 1 {
                    qualityMenu
                }

                // Speed picker — inline Menu instead of a full sheet
                speedMenu

                // Audio track picker — inline Menu (context-menu style)
                if videoManager.audioTracks.count > 1 {
                    audioTrackMenu
                }

                // Subtitle picker — inline Menu (context-menu style)
                if !videoManager.subtitleTracks.isEmpty {
                    subtitleMenu
                }

                // AirPlay
                #if os(iOS)
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                        .tint(.white)
                #endif
            }
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
                        resetControlsTimer()
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

    /// Inline speed picker presented as a compact Menu (context-menu style).
    private var speedMenu: some View {
        Menu {
            Picker(
                "Playback Speed",
                selection: Binding(
                    get: { videoManager.playbackSpeed },
                    set: { newSpeed in
                        videoManager.setSpeed(newSpeed)
                        Defaults[.videoPlaybackSpeed] = newSpeed
                        resetControlsTimer()
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

    /// Speed label: "1×" for normal, "1.5×" etc for other speeds.
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

    // MARK: - Seek Slider

    /// The time to display — prioritizes gesture seeking, then slider seeking, then actual time.
    private var displayTime: TimeInterval {
        if isGestureSeeking { return gestureSeekTime }
        if isSeeking { return seekTime }
        return videoManager.currentTime
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

    // MARK: - Subtitle Overlay

    /// White text with a black stroke outline — standard subtitle appearance.
    @ViewBuilder
    private func subtitleLabel(_ text: String) -> some View {
        let outlineWidth: CGFloat = 1.2
        ZStack {
            // Black stroke: render the same text offset in 8 directions
            ForEach(
                [
                    CGSize(width: -outlineWidth, height: -outlineWidth),
                    CGSize(width: 0, height: -outlineWidth),
                    CGSize(width: outlineWidth, height: -outlineWidth),
                    CGSize(width: -outlineWidth, height: 0),
                    CGSize(width: outlineWidth, height: 0),
                    CGSize(width: -outlineWidth, height: outlineWidth),
                    CGSize(width: 0, height: outlineWidth),
                    CGSize(width: outlineWidth, height: outlineWidth),
                ],
                id: \.debugDescription
            ) { offset in
                Text(text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .offset(x: offset.width, y: offset.height)
            }
            // White fill on top
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Subtitle Menu

    /// Inline subtitle picker presented as a compact Menu (context-menu style).
    /// Uses -1 as a sentinel for "Off" since Picker needs a hashable, non-optional tag.
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
                        resetControlsTimer()
                    }
                )
            ) {
                Text("Off").tag(-1)

                ForEach(videoManager.subtitleTracks) { track in
                    subtitleTrackLabel(for: track)
                        .tag(track.id)
                }
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

    /// Label for a single subtitle track option inside the picker.
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

    /// Inline audio track picker presented as a compact Menu (context-menu style).
    private var audioTrackMenu: some View {
        Menu {
            Picker(
                "Audio Track",
                selection: Binding(
                    get: { videoManager.selectedAudioTrackIndex ?? 0 },
                    set: { newIndex in
                        videoManager.selectAudioTrack(at: newIndex)
                        resetControlsTimer()
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

    /// Label for a single audio track option inside the picker.
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

    // MARK: - Next Episode Countdown

    // MARK: - Skip Segment Button

    @ViewBuilder
    private var skipSegmentButton: some View {
        if let segment = activeSkippableSegment {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        videoManager.seek(to: segment.endTime)
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
            .animation(.spring(duration: 0.4), value: activeSkippableSegment?.id)
        }
    }

    /// The currently active skippable segment based on playback position.
    private var activeSkippableSegment: MediaSegment? {
        mediaSegments.first { $0.contains(time: videoManager.currentTime) }
    }

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
                            videoManager.dismissNextEpisodeCountdown()
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
                        // Next episode thumbnail
                        MediaImage.videoThumbnail(url: thumbnailURL(for: next), cornerRadius: 6)
                            .frame(width: 100)

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
                .background(
                    .ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)
                )
                .environment(\.colorScheme, .dark)
            }
            .padding(24)
        }
    }

    // MARK: - Setup

    private func setupAndPlay() {
        // Restore persisted playback speed
        let savedSpeed = Defaults[.videoPlaybackSpeed]
        if savedSpeed != 1.0 {
            videoManager.setSpeed(savedSpeed)
        }

        // Wire playback reporting callbacks
        let provider = authManager.provider
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
            coordinator.dismiss()
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

        // Don't schedule auto-hide yet — controls stay visible until
        // playback has actually started (detected via onChange handlers).
        // For instant-start local files where isBuffering is never true,
        // the isPlaying onChange will catch it immediately.
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
        showControls = true
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
