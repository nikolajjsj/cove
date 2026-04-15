import CoveUI
import Models
import SwiftUI

/// A modern, visually rich media info section that replaces the old
/// horizontally-scrolling metadata pills.
///
/// Displays three logical groups:
/// 1. **Rating badges** — prominent side-by-side cards for community
///    and critic ratings with source branding (IMDb, RT).
/// 2. **Technical info card** — a clean material card with labeled rows
///    for video resolution, HDR, codecs, audio channels, and bitrate.
/// 3. **Played indicator** — a subtle label when the user has watched
///    the content.
///
/// Each group gracefully hides when its data is unavailable, so the
/// section adapts to whatever metadata the server provides.
///
/// ```swift
/// MediaInfoSection(item: item, displayItem: displayItem)
/// ```
struct MediaInfoSection: View {
    let item: MediaItem
    let displayItem: MediaItem

    // MARK: - Computed Data

    private var communityRating: Double? {
        guard let r = item.communityRating, r > 0 else { return nil }
        return r
    }

    private var criticRating: Double? {
        guard let r = item.criticRating, r > 0 else { return nil }
        return r
    }

    private var hasImdb: Bool {
        displayItem.providerIds?.imdb != nil
    }

    private var hasRatings: Bool {
        communityRating != nil || criticRating != nil
    }

    private var videoStream: MediaStream? {
        displayItem.mediaStreams?.first { $0.type == .video }
    }

    private var audioStream: MediaStream? {
        displayItem.mediaStreams?.first { $0.type == .audio }
    }

    private var hasTechnicalInfo: Bool {
        videoStream != nil || audioStream != nil
    }

    private var userData: UserData? {
        item.userData
    }

    // MARK: - Body

    var body: some View {
        if hasRatings || hasTechnicalInfo || userData?.isPlayed == true {
            VStack(alignment: .leading, spacing: 12) {
                if hasRatings {
                    RatingCardsRow(
                        communityRating: communityRating,
                        criticRating: criticRating,
                        hasImdb: hasImdb
                    )
                }

                if hasTechnicalInfo {
                    TechnicalInfoCard(
                        videoStream: videoStream,
                        audioStream: audioStream
                    )
                }

                if let userData, userData.isPlayed {
                    PlayedStatusLabel(playCount: userData.playCount)
                }
            }
        }
    }
}

// MARK: - Rating Badges Row

/// Two side-by-side rating cards for community and critic scores.
private struct RatingCardsRow: View {
    let communityRating: Double?
    let criticRating: Double?
    let hasImdb: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let communityRating {
                RatingCard(
                    icon: "star.fill",
                    source: hasImdb ? "IMDb" : "Rating",
                    value: formattedCommunityRating(communityRating),
                    tint: .yellow
                )
            }

            if let criticRating {
                RatingCard(
                    icon: "heart.fill",
                    source: "Rotten Tomatoes",
                    value: "\(Int(criticRating))%",
                    tint: criticRating >= 60 ? .green : .red
                )
            }
        }
    }

    private func formattedCommunityRating(_ rating: Double) -> String {
        if rating.truncatingRemainder(dividingBy: 1) == 0 {
            return rating.formatted(.number.precision(.fractionLength(0)))
        }
        return rating.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Rating Card

/// A single rating card with an icon, source label, and
/// a prominent score.
///
/// Uses a subtle material background with a leading color accent
/// strip for visual identity.
private struct RatingCard: View {
    let icon: String
    let source: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            // Color accent strip
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.gradient)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(tint)

                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)
                }

                Text(value)
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Technical Info Card

/// A material card showing video and audio technical specifications
/// in clean, labeled rows separated by subtle dividers.
private struct TechnicalInfoCard: View {
    let videoStream: MediaStream?
    let audioStream: MediaStream?

    var body: some View {
        VStack(spacing: 0) {
            if let videoStream {
                TechRow(
                    icon: "tv",
                    label: "Video",
                    details: videoDetails(videoStream)
                )

                if audioStream != nil || videoBitrate(videoStream) != nil {
                    Divider()
                        .padding(.leading, 40)
                }
            }

            if let audioStream {
                TechRow(
                    icon: "speaker.wave.2.fill",
                    label: "Audio",
                    details: audioDetails(audioStream)
                )

                if let videoStream, videoBitrate(videoStream) != nil {
                    Divider()
                        .padding(.leading, 40)
                }
            }

            if let videoStream, let bitrate = videoBitrate(videoStream) {
                TechRow(
                    icon: "speedometer",
                    label: "Bitrate",
                    details: bitrate
                )
            }
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Video Details

    private func videoDetails(_ stream: MediaStream) -> String {
        var parts: [String] = []

        if let res = resolutionLabel(width: stream.width ?? 0) {
            parts.append(res)
        }

        if let codec = videoCodecLabel(stream.codec) {
            parts.append(codec)
        }

        if let hdr = hdrLabel(videoRange: stream.videoRange, videoRangeType: stream.videoRangeType)
        {
            parts.append(hdr)
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Audio Details

    private func audioDetails(_ stream: MediaStream) -> String {
        var parts: [String] = []

        if let channels = channelLabel(stream.channels ?? 0) {
            parts.append(channels)
        }

        if let codec = audioCodecLabel(stream.codec) {
            parts.append(codec)
        }

        if let language = stream.language, !language.isEmpty {
            let locale = Locale.current
            if let name = locale.localizedString(forLanguageCode: language) {
                parts.append(name)
            }
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Bitrate

    private func videoBitrate(_ stream: MediaStream) -> String? {
        guard let bitrate = stream.bitrate, bitrate > 0 else { return nil }
        let mbps = Double(bitrate) / 1_000_000.0
        if mbps >= 10 {
            return "\(Int(mbps)) Mbps"
        } else if mbps >= 1 {
            return mbps.formatted(.number.precision(.fractionLength(1))) + " Mbps"
        } else {
            let kbps = bitrate / 1000
            return "\(kbps) kbps"
        }
    }

    // MARK: - Formatting Helpers

    private func resolutionLabel(width: Int) -> String? {
        if width >= 3840 { return "4K" }
        if width >= 1920 { return "1080p" }
        if width >= 1280 { return "720p" }
        if width > 0 { return "SD" }
        return nil
    }

    private func hdrLabel(videoRange: String?, videoRangeType: String?) -> String? {
        if let rangeType = videoRangeType?.lowercased() {
            switch rangeType {
            case "dovi", "dolbyvision": return "Dolby Vision"
            case "hdr10plus": return "HDR10+"
            case "hdr10": return "HDR10"
            default: break
            }
        }
        if let range = videoRange?.uppercased(), range == "HDR" {
            return "HDR"
        }
        return nil
    }

    private func videoCodecLabel(_ codec: String?) -> String? {
        guard let codec, !codec.isEmpty else { return nil }
        switch codec.lowercased() {
        case "hevc", "h265", "h.265": return "HEVC"
        case "h264", "h.264", "avc": return "H.264"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        case "vc1": return "VC-1"
        case "mpeg2video", "mpeg2": return "MPEG-2"
        case "mpeg4": return "MPEG-4"
        default: return codec.uppercased()
        }
    }

    private func audioCodecLabel(_ codec: String?) -> String? {
        guard let codec, !codec.isEmpty else { return nil }
        switch codec.lowercased() {
        case "truehd": return "TrueHD"
        case "eac3": return "EAC-3"
        case "ac3": return "AC-3"
        case "dts": return "DTS"
        case "dca": return "DTS"
        case "dtshd": return "DTS-HD MA"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "vorbis": return "Vorbis"
        case "mp3": return "MP3"
        case "pcm_s16le", "pcm_s24le", "pcm": return "PCM"
        default: return codec.uppercased()
        }
    }

    private func channelLabel(_ channels: Int) -> String? {
        switch channels {
        case 8: return "7.1 Surround"
        case 6: return "5.1 Surround"
        case 2: return "Stereo"
        case 1: return "Mono"
        default: return nil
        }
    }
}

// MARK: - Tech Row

/// A single row inside the technical info card with an icon, label,
/// and detail text.
private struct TechRow: View {
    let icon: String
    let label: String
    let details: String

    var body: some View {
        if !details.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Played Status Label

/// A subtle label indicating the user has watched the content.
private struct PlayedStatusLabel: View {
    let playCount: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            if playCount > 1 {
                Text("Watched \(playCount) times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Watched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Full Info") {
        ScrollView {
            VStack(spacing: 20) {
                MediaInfoSection(
                    item: MediaItem(
                        id: ItemID("1"),
                        title: "Interstellar",
                        mediaType: .movie,
                        communityRating: 8.7,
                        criticRating: 73,
                        userData: UserData(
                            isFavorite: false,
                            playbackPosition: 0,
                            playCount: 3,
                            isPlayed: true,
                            lastPlayedDate: nil
                        )
                    ),
                    displayItem: MediaItem(
                        id: ItemID("1"),
                        title: "Interstellar",
                        mediaType: .movie,
                        providerIds: ProviderIds(imdb: "tt0816692", tmdb: "157336", tvdb: nil),
                        mediaStreams: [
                            MediaStream(
                                index: 0, type: .video, codec: "hevc",
                                width: 3840, height: 2160, bitrate: 42_000_000,
                                videoRange: "HDR", videoRangeType: "HDR10"
                            ),
                            MediaStream(
                                index: 1, type: .audio, codec: "truehd",
                                language: "en", channels: 8
                            ),
                        ]
                    )
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    #Preview("Ratings Only") {
        ScrollView {
            MediaInfoSection(
                item: MediaItem(
                    id: ItemID("2"),
                    title: "Breaking Bad",
                    mediaType: .series,
                    communityRating: 9.5,
                    criticRating: 96
                ),
                displayItem: MediaItem(
                    id: ItemID("2"),
                    title: "Breaking Bad",
                    mediaType: .series,
                    providerIds: ProviderIds(imdb: "tt0903747", tmdb: nil, tvdb: nil)
                )
            )
            .padding(.horizontal)
        }
    }

    #Preview("No Data") {
        MediaInfoSection(
            item: MediaItem(id: ItemID("3"), title: "Empty", mediaType: .movie),
            displayItem: MediaItem(id: ItemID("3"), title: "Empty", mediaType: .movie)
        )
        .padding()
    }
#endif
