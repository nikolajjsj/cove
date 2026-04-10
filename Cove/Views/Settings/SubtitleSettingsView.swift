import Defaults
import SwiftUI

/// A settings view for customizing subtitle appearance during video playback.
///
/// Includes pickers for size, color, and background style, along with a live
/// preview that shows how subtitles will look with the current settings.
struct SubtitleSettingsView: View {
    @Default(.subtitleSize) private var subtitleSize
    @Default(.subtitleColor) private var subtitleColor
    @Default(.subtitleBackground) private var subtitleBackground

    var body: some View {
        List {
            Section {
                SubtitlePreview(
                    size: subtitleSize,
                    color: subtitleColor,
                    background: subtitleBackground
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Size") {
                Picker("Subtitle Size", selection: $subtitleSize) {
                    ForEach(SubtitleSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Color") {
                Picker(selection: $subtitleColor) {
                    ForEach(SubtitleColor.allCases, id: \.self) { color in
                        Label {
                            Text(color.displayName)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(color.color)
                        }
                        .tag(color)
                    }
                } label: {
                    Label("Text Color", systemImage: "paintbrush")
                }
                .pickerStyle(.menu)
            }

            Section("Background Style") {
                Picker(selection: $subtitleBackground) {
                    ForEach(SubtitleBackground.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                } label: {
                    Label("Background", systemImage: "rectangle.on.rectangle")
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Subtitles")
    }
}

// MARK: - Live Preview

/// Shows a live preview of subtitle appearance against a dark gradient background.
private struct SubtitlePreview: View {
    let size: SubtitleSize
    let color: SubtitleColor
    let background: SubtitleBackground

    var body: some View {
        ZStack {
            // Simulated video background
            LinearGradient(
                colors: [.black, .gray.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.15))
            }

            VStack {
                Spacer()
                SubtitleTextView(
                    text: "This is a subtitle preview.",
                    size: size,
                    color: color,
                    background: background
                )
                .padding(.bottom)
            }
        }
        .frame(height: 200)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SubtitleSettingsView()
    }
}
