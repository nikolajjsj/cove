import Defaults
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

#if !os(tvOS)

    // MARK: - Video Controls Overlay

    struct VideoControlsOverlay: View {
        let item: MediaItem
        let streamInfo: StreamInfo
        let videoManager: VideoPlaybackManager
        let coordinator: VideoPlayerCoordinator
        let authManager: AuthManager
        let isLoadingVideo: Bool
        @Binding var isSeeking: Bool
        @Binding var seekTime: TimeInterval
        let isGestureSeeking: Bool
        let gestureSeekTime: TimeInterval
        @Binding var backwardSkipTrigger: Int
        @Binding var forwardSkipTrigger: Int
        @Binding var showChapterList: Bool
        @Binding var showSubtitleSearch: Bool
        let onDismiss: () -> Void
        let onResetTimer: () -> Void
        let onCancelTimer: () -> Void

        var body: some View {
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

                // Center controls — float independently so the play button sits at
                // the exact center of the screen regardless of top/bottom bar heights.
                PlayerCenterControls(
                    videoManager: videoManager,
                    backwardSkipTrigger: $backwardSkipTrigger,
                    forwardSkipTrigger: $forwardSkipTrigger,
                    onSkipBackward: {
                        videoManager.skipBackward(Defaults[.skipBackwardInterval])
                    },
                    onSkipForward: { videoManager.skipForward(Defaults[.skipForwardInterval]) },
                    onResetTimer: onResetTimer
                )

                // Top bar anchored to the top edge
                VStack(spacing: 0) {
                    PlayerTopBar(
                        item: item,
                        videoManager: videoManager,
                        onDismiss: onDismiss,
                        onShowChapters: {
                            showChapterList = true
                            onCancelTimer()
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    Spacer()
                }

                // Bottom bar anchored to the bottom edge
                VStack(spacing: 0) {
                    Spacer()
                    PlayerBottomBar(
                        item: item,
                        streamInfo: streamInfo,
                        videoManager: videoManager,
                        coordinator: coordinator,
                        authManager: authManager,
                        isSeeking: $isSeeking,
                        seekTime: $seekTime,
                        isGestureSeeking: isGestureSeeking,
                        gestureSeekTime: gestureSeekTime,
                        showSubtitleSearch: $showSubtitleSearch,
                        onControlsInteraction: StableAction(onResetTimer)
                    )
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
    }

#endif
