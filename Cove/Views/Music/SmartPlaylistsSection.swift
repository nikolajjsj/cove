import SwiftUI

// MARK: - Section

/// A "Made for You" section on the music library home screen showing
/// hardcoded smart playlist presets as visually rich gradient cards
/// in a horizontal scroll rail.
///
/// Each card is a `NavigationLink` that pushes a `SmartPlaylistDetailView`
/// via the centralized navigation destination registration.
struct SmartPlaylistsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Made for You")
                .font(.title2)
                .bold()
                .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(SmartPlaylist.presets) { preset in
                        NavigationLink(value: preset) {
                            SmartPlaylistCard(preset: preset)
                        }
                        .buttonStyle(SmartPlaylistCardButtonStyle())
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Smart Playlists Section") {
        NavigationStack {
            ScrollView {
                SmartPlaylistsSection()
                    .padding(.vertical)
            }
        }
    }
#endif
