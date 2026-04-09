import Foundation

/// DTO for a segment returned by the Intro Skipper plugin.
///
/// The plugin exposes `GET /Episode/{itemId}/IntroSkipperSegments` which returns
/// a dictionary keyed by segment type ("Introduction", "Credits") with values of this type.
///
/// Different plugin versions use different field names and key casing:
/// - Newer versions (jumoog/intro-skipper): `Start`, `End`
/// - Older versions (ConfusedPolarBear): `IntroStart`, `IntroEnd`
/// - Either may use PascalCase, camelCase, or snake_case
///
/// This type uses a custom `Decodable` initializer that tries all known key variants
/// to decode each field reliably regardless of the server's JSON format.
public struct IntroSkipperSegment: Sendable {
    public let episodeId: String?
    public let valid: Bool?
    /// Segment start time in seconds. Sourced from `Start`, `IntroStart`, or `ShowSkipPromptAt`.
    public let start: Double?
    /// Segment end time in seconds. Sourced from `End`, `IntroEnd`, or `HideSkipPromptAt`.
    public let end: Double?
}

// MARK: - Case-Insensitive Decodable

extension IntroSkipperSegment: Decodable {

    /// A CodingKey that can represent any string key in the JSON payload.
    private struct FlexibleCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)

        // Build a case-insensitive lookup: lowercased key → actual container key
        var keyMap = [String: FlexibleCodingKey]()
        for key in container.allKeys {
            keyMap[key.stringValue.lowercased()] = key
        }

        /// Try to decode a value by looking up any of the provided candidate key names
        /// (compared case-insensitively against what's actually in the JSON).
        func decode<T: Decodable>(_ type: T.Type, candidates: [String]) -> T? {
            for candidate in candidates {
                if let actualKey = keyMap[candidate.lowercased()],
                    let value = try? container.decodeIfPresent(type, forKey: actualKey)
                {
                    return value
                }
            }
            return nil
        }

        episodeId = decode(String.self, candidates: ["EpisodeId", "episodeId", "episode_id"])
        valid = decode(Bool.self, candidates: ["Valid", "valid"])

        // Start time: newer plugins use "Start", older use "IntroStart",
        // fall back to "ShowSkipPromptAt" if neither exists
        start = decode(
            Double.self,
            candidates: [
                "Start", "start",
                "IntroStart", "introStart", "intro_start",
                "ShowSkipPromptAt", "showSkipPromptAt", "show_skip_prompt_at",
            ]
        )

        // End time: newer plugins use "End", older use "IntroEnd",
        // fall back to "HideSkipPromptAt" if neither exists
        end = decode(
            Double.self,
            candidates: [
                "End", "end",
                "IntroEnd", "introEnd", "intro_end",
                "HideSkipPromptAt", "hideSkipPromptAt", "hide_skip_prompt_at",
            ]
        )
    }
}

// MARK: - Encodable

extension IntroSkipperSegment: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKey.self)
        try container.encodeIfPresent(
            episodeId, forKey: FlexibleCodingKey(stringValue: "EpisodeId")!)
        try container.encodeIfPresent(valid, forKey: FlexibleCodingKey(stringValue: "Valid")!)
        try container.encodeIfPresent(start, forKey: FlexibleCodingKey(stringValue: "Start")!)
        try container.encodeIfPresent(end, forKey: FlexibleCodingKey(stringValue: "End")!)
    }
}
