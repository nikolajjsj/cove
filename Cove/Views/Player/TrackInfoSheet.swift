import Models
import SwiftUI

/// Displays technical metadata for the currently playing track.
struct TrackInfoSheet: View {
    let track: Track

    var body: some View {
        NavigationStack {
            List {
                if let codec = track.codec {
                    row(label: "Format", value: codec.uppercased())
                }
                if let bitRate = track.bitRate {
                    row(label: "Bit Rate", value: bitRate.formatted(.number) + " kbps")
                }
                if let sampleRate = track.sampleRate {
                    row(label: "Sample Rate", value: sampleRate.formatted(.number) + " Hz")
                }
                if let channelCount = track.channelCount {
                    row(label: "Channels", value: channelLabel(for: channelCount))
                }
                if let duration = track.duration {
                    row(
                        label: "Duration",
                        value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                }
                if let trackNumber = track.trackNumber {
                    row(label: "Track", value: trackNumber.formatted())
                }
                if let discNumber = track.discNumber {
                    row(label: "Disc", value: discNumber.formatted())
                }
                if let albumName = track.albumName {
                    row(label: "Album", value: albumName)
                }
                if let artistName = track.artistName {
                    row(label: "Artist", value: artistName)
                }
            }
            .navigationTitle("Track Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func row(label: String, value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private func channelLabel(for count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1 Surround"
        case 8: return "7.1 Surround"
        default: return "\(count) channels"
        }
    }
}
