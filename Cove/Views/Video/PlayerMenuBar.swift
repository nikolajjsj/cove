import Defaults
import JellyfinProvider
import Models
import PlaybackEngine
import SwiftUI

#if !os(tvOS)

    // MARK: - Player Menu Bar

    /// Extracted menu bar for the video player controls.
    ///
    /// This is a separate `View` struct (not a computed property on `VideoPlayerView`)
    /// so that it gets its own `@Observable` tracking scope. This prevents the menus
    /// from re-rendering every time `videoManager.currentTime` changes (~10×/sec),
    /// which caused visible flickering/flashing of menu buttons and dismissed open menus.
    ///
    /// The `onControlsInteraction` callback uses `StableAction` (always-equal wrapper)
    /// so that closure identity changes don't cause SwiftUI to treat this view as modified.
    struct PlayerMenuBar: View {
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
                    QualityMenuView(
                        coordinator: coordinator,
                        videoManager: videoManager,
                        onControlsInteraction: onControlsInteraction
                    )
                }

                // Speed picker
                SpeedMenuView(
                    videoManager: videoManager,
                    onControlsInteraction: onControlsInteraction
                )

                // Audio track picker
                if videoManager.audioTracks.count > 1 {
                    AudioTrackMenuView(
                        videoManager: videoManager,
                        onControlsInteraction: onControlsInteraction
                    )
                }

                // Subtitle picker
                SubtitleMenuView(
                    item: item,
                    streamInfo: streamInfo,
                    videoManager: videoManager,
                    authManager: authManager,
                    showSubtitleSearch: $showSubtitleSearch,
                    onControlsInteraction: onControlsInteraction
                )

                // AirPlay
                #if os(iOS)
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                        .tint(.white)
                #endif
            }
        }

        // MARK: - Quality Menu

        private struct QualityMenuView: View {
            let coordinator: VideoPlayerCoordinator
            let videoManager: VideoPlaybackManager
            let onControlsInteraction: StableAction

            var body: some View {
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
                    Image(
                        systemName: coordinator.activeQuality == .auto ? "dial.low" : "dial.high"
                    )
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        coordinator.activeQuality == .auto ? .white : Color.accentColor
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
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
        }

        // MARK: - Speed Menu

        private struct SpeedMenuView: View {
            let videoManager: VideoPlaybackManager
            let onControlsInteraction: StableAction

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

            var body: some View {
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
                        .contentShape(.rect)
                }
            }
        }

        // MARK: - Subtitle Menu

        private struct SubtitleMenuView: View {
            let item: MediaItem
            let streamInfo: StreamInfo
            let videoManager: VideoPlaybackManager
            let authManager: AuthManager
            @Binding var showSubtitleSearch: Bool
            let onControlsInteraction: StableAction

            var body: some View {
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
                    .contentShape(.rect)
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
        }

        // MARK: - Audio Track Menu

        private struct AudioTrackMenuView: View {
            let videoManager: VideoPlaybackManager
            let onControlsInteraction: StableAction

            var body: some View {
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
                        .contentShape(.rect)
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
    }

#endif
