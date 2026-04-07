import CoveUI
import JellyfinProvider
import MediaServerKit
import Models
import NukeUI
import PlaybackEngine
import SwiftUI

/// Full-screen audio player presented as a modal sheet.
///
/// Architecture: a three-page horizontal `TabView` (artwork, lyrics, queue)
/// with persistent playback controls below. The background is a dominant-color
/// gradient extracted from the current track's album artwork.
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
            Spacer()

            // Swipeable pages
            TabView(selection: $currentPage) {
                // Page 1: Artwork
                artworkPage(track: track).tag(PlayerPage.artwork)

                // Page 2: Lyrics
                LyricsView(track: track).tag(PlayerPage.lyrics)

                // Page 3: Queue
                QueueView().tag(PlayerPage.queue)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .aspectRatio(1, contentMode: .fit)
            .padding(24)

            Spacer()

            // Persistent controls
            PlayerControlsView(track: track, currentPage: $currentPage)
                .padding(.bottom, 8)
        }
        .background(backgroundGradient)
        .preferredColorScheme(dominantColor.isLight ? .dark : nil)
        .onChange(of: track.id) { _, _ in
            updateDominantColor(for: track)
        }
        .task(id: track.id) {
            await extractColorAsync(for: track)
        }
    }

    // MARK: - Page 1: Artwork

    @ViewBuilder
    private func artworkPage(track: Track) -> some View {
        VStack {
            Spacer()

            MediaImage.artwork(url: artworkURL(for: track), cornerRadius: 12)
                .frame(maxWidth: 600, maxHeight: 600)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.3), value: track.id)

            Spacer()
        }
        .padding(.top, 12)
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

        // Return cached result if available
        if let cached = colorCache[cacheKey] {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = cached
            }
            return
        }

        // Load image and extract colors
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
