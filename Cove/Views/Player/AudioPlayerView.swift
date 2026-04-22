import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import NukeUI
import PlaybackEngine
import SwiftUI

/// Full-screen audio player presented as a modal sheet.
///
/// Layout:
///  - A dynamic content area switches between artwork mode and secondary mode
///    (queue / lyrics). Only this area participates in page transitions.
///  - A persistent section — scrubber, transport controls, and the bottom
///    toolbar — is always pinned at the same vertical position so the
///    scrubber never jumps when switching pages.
struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage: PlayerPage = .artwork
    @State private var dominantColor: DominantColorExtractor.ExtractionResult =
        DominantColorExtractor.fallback
    @State private var colorCache: [String: DominantColorExtractor.ExtractionResult] = [:]

    private var player: AudioPlaybackManager { appState.audioPlayer }
    private var queue: PlayQueue { player.queue }

    var body: some View {
        Group {
            if let track = queue.currentTrack {
                playerContent(track: track)
            } else {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "music.note",
                    description: Text("Select a track to start listening.")
                )
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Player Content

    @ViewBuilder
    private func playerContent(track: Track) -> some View {
        VStack(spacing: 0) {
            // Dynamic area — only this region transitions between pages
            Group {
                if currentPage == .artwork {
                    artworkContent(track: track).transition(.opacity)
                } else {
                    secondaryContent(track: track).transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            // Persistent section — fixed position, never participates in transitions
            PlayerControlsView()
            PlayerBottomToolbar(currentPage: $currentPage)
        }
        .background(backgroundGradient)
        .preferredColorScheme(.dark)
        .onChange(of: track.id) { _, _ in
            updateDominantColor(for: track)
        }
        .task(id: track.id) {
            await extractColorAsync(for: track)
        }
    }

    // MARK: - Artwork Content

    /// Large album art fills the dynamic area; the adaptive track info row
    /// (no thumbnail, with live-lyric preview) anchors at the bottom of this
    /// area — directly above the persistent scrubber.
    @ViewBuilder
    private func artworkContent(track: Track) -> some View {
        VStack(spacing: 0) {
            VStack {
                Spacer()
                MediaImage.artwork(url: artworkURL(for: track), cornerRadius: 12)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.3), value: track.id)
                Spacer()
            }
            .frame(maxHeight: .infinity)

            PlayerTrackInfoRow(track: track, showThumbnail: false, showLyricPreview: true)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Secondary Content (Lyrics / Queue)

    /// Compact track info (with thumbnail) anchors at the top; the queue or
    /// lyrics scroll view fills the remaining space below.
    @ViewBuilder
    private func secondaryContent(track: Track) -> some View {
        VStack(spacing: 0) {
            PlayerTrackInfoRow(track: track, showThumbnail: true, showLyricPreview: false)

            Divider()
                .overlay(.white.opacity(0.2))

            Group {
                if currentPage == .queue {
                    QueueView(showCurrentTrack: false)
                } else {
                    LyricsView(track: track)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: currentPage)
        }
    }

    // MARK: - Background Gradient

    @ViewBuilder
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                dominantColor.primary.opacity(0.7),
                dominantColor.darkened.opacity(0.9),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: dominantColor.primary)
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.3)
        }
    }

    // MARK: - Dominant Color Extraction

    private func updateDominantColor(for track: Track) {
        let cacheKey = track.albumId?.rawValue ?? track.id.rawValue
        if let cached = colorCache[cacheKey] {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = cached
            }
        }
    }

    private func extractColorAsync(for track: Track) async {
        let cacheKey = track.albumId?.rawValue ?? track.id.rawValue

        if let cached = colorCache[cacheKey] {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = cached
            }
            return
        }

        guard let url = artworkURL(for: track) else {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = DominantColorExtractor.fallback
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data),
                    let cgImage = uiImage.cgImage
                else {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        dominantColor = DominantColorExtractor.fallback
                    }
                    return
                }
            #elseif canImport(AppKit)
                guard let nsImage = NSImage(data: data),
                    let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        dominantColor = DominantColorExtractor.fallback
                    }
                    return
                }
            #else
                withAnimation(.easeInOut(duration: 0.6)) {
                    dominantColor = DominantColorExtractor.fallback
                }
                return
            #endif

            #if canImport(CoreGraphics)
                let result = DominantColorExtractor.extractColors(from: cgImage)
                colorCache[cacheKey] = result
                withAnimation(.easeInOut(duration: 0.6)) {
                    dominantColor = result
                }
            #endif
        } catch {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = DominantColorExtractor.fallback
            }
        }
    }

    // MARK: - Helpers

    private func artworkURL(for track: Track) -> URL? {
        let itemId = track.albumId ?? track.id
        return authManager.provider.imageURL(
            for: itemId, type: .primary, maxSize: CGSize(width: 600, height: 600))
    }
}

#Preview {
    let state = AppState.preview
    AudioPlayerView()
        .environment(state)
        .environment(state.authManager)
}
