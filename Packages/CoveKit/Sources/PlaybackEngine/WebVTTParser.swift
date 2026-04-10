import Foundation

/// A single subtitle cue with timing and text.
public struct SubtitleCue: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
}

/// Parses WebVTT and SRT subtitle files into an array of `SubtitleCue`.
public enum WebVTTParser {

    /// Parse a WebVTT or SRT string into subtitle cues, sorted by start time.
    public static func parse(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []

        // Normalize line endings
        let normalized =
            content
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")

        // Split into blocks separated by blank lines
        let blocks = normalized.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            // Find the timestamp line (contains "-->")
            guard let timestampLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timestampLine = lines[timestampLineIndex]

            // Parse timestamps: "00:01:23.456 --> 00:01:25.789" or with position metadata after
            let parts = timestampLine.components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }

            guard let startTime = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
                let endTime = parseTimestamp(
                    parts[1].trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: " ").first
                        ?? parts[1].trimmingCharacters(in: .whitespaces)
                )
            else { continue }

            // Collect text lines after the timestamp
            let textLines = lines.dropFirst(timestampLineIndex + 1)
                .filter { !$0.isEmpty }

            guard !textLines.isEmpty else { continue }

            let rawText = textLines.joined(separator: "\n")
            let cleanText = stripHTMLTags(rawText)

            guard !cleanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            cues.append(SubtitleCue(startTime: startTime, endTime: endTime, text: cleanText))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private

    /// Parse a timestamp string like "00:01:23.456" or "01:23.456" or "00:01:23,456" (SRT).
    private static func parseTimestamp(_ string: String) -> TimeInterval? {
        // Normalize SRT comma separator to dot
        let normalized = string.replacing(",", with: ".")
        let components = normalized.components(separatedBy: ":")

        switch components.count {
        case 3:
            // HH:MM:SS.mmm
            guard let hours = Double(components[0].trimmingCharacters(in: .whitespaces)),
                let minutes = Double(components[1].trimmingCharacters(in: .whitespaces)),
                let seconds = Double(components[2].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return hours * 3600 + minutes * 60 + seconds

        case 2:
            // MM:SS.mmm
            guard let minutes = Double(components[0].trimmingCharacters(in: .whitespaces)),
                let seconds = Double(components[1].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return minutes * 60 + seconds

        default:
            return nil
        }
    }

    /// Strip HTML-style tags from subtitle text (e.g. <b>, <i>, </b>).
    private static func stripHTMLTags(_ string: String) -> String {
        string.replacing(/<[^>]+>/, with: "")
    }
}
