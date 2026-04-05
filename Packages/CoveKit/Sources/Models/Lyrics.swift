import Foundation

public struct Lyrics: Codable, Hashable, Sendable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines
    }
}

public struct LyricLine: Codable, Hashable, Sendable {
    public let startTime: TimeInterval?
    public let text: String

    public init(startTime: TimeInterval? = nil, text: String) {
        self.startTime = startTime
        self.text = text
    }
}
