import Foundation

public struct MediaStream: Codable, Hashable, Sendable {
    public let index: Int
    public let type: MediaStreamType
    public let codec: String
    public let language: String?
    public let title: String?
    public let isExternal: Bool

    public init(
        index: Int,
        type: MediaStreamType,
        codec: String,
        language: String? = nil,
        title: String? = nil,
        isExternal: Bool = false
    ) {
        self.index = index
        self.type = type
        self.codec = codec
        self.language = language
        self.title = title
        self.isExternal = isExternal
    }
}
