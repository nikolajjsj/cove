import Foundation

/// Static helpers for formatting media stream properties (codec, resolution, HDR, etc.)
/// into human-readable labels.
///
/// Used by both ``MetadataPill`` factory methods and detail view technical info cards
/// to ensure consistent labelling across the app.
public enum MediaStreamLabels {

    /// Returns a human-readable resolution label, or `nil` if width is zero.
    public static func resolution(width: Int) -> String? {
        if width >= 3840 { return "4K" }
        if width >= 1920 { return "1080p" }
        if width >= 1280 { return "720p" }
        if width > 0 { return "SD" }
        return nil
    }

    /// Returns an HDR type label, or `nil` if no HDR is detected.
    public static func hdr(videoRange: String?, videoRangeType: String?) -> String? {
        if let rangeType = videoRangeType?.lowercased() {
            switch rangeType {
            case "dovi", "dolbyvision": return "Dolby Vision"
            case "hdr10plus": return "HDR10+"
            case "hdr10": return "HDR10"
            default: break
            }
        }
        if let range = videoRange?.uppercased(), range == "HDR" { return "HDR" }
        return nil
    }

    /// Returns a normalized video codec label, or `nil` if `codec` is nil/empty.
    public static func videoCodec(_ codec: String?) -> String? {
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

    /// Returns a normalized audio codec label, or `nil` if `codec` is nil/empty.
    public static func audioCodec(_ codec: String?) -> String? {
        guard let codec, !codec.isEmpty else { return nil }
        switch codec.lowercased() {
        case "truehd": return "TrueHD"
        case "eac3": return "EAC-3"
        case "ac3": return "AC-3"
        case "dts", "dca": return "DTS"
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

    /// Returns an audio channels label (e.g. "7.1 Surround"), or `nil` for unsupported counts.
    public static func channels(_ channels: Int) -> String? {
        switch channels {
        case 8: return "7.1 Surround"
        case 6: return "5.1 Surround"
        case 2: return "Stereo"
        case 1: return "Mono"
        default: return nil
        }
    }

    /// Returns a formatted bitrate string (e.g. "42 Mbps", "8.5 Mbps", "800 kbps"), or `nil`.
    public static func bitrate(_ bitrate: Int?) -> String? {
        guard let bitrate, bitrate > 0 else { return nil }
        let mbps = Double(bitrate) / 1_000_000.0
        if mbps >= 10 { return "\(Int(mbps)) Mbps" }
        if mbps >= 1 { return mbps.formatted(.number.precision(.fractionLength(1))) + " Mbps" }
        return "\(bitrate / 1000) kbps"
    }
}
