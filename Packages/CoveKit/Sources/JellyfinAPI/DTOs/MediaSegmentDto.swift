import Foundation

/// DTO for a media segment returned by Jellyfin's MediaSegments API.
public struct MediaSegmentDto: Codable, Sendable {
    public let id: String?
    public let itemId: String?
    public let type: String?
    public let startTicks: Int64?
    public let endTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case itemId = "ItemId"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }
}

/// Wrapper for the MediaSegments API response.
public struct MediaSegmentQueryResult: Codable, Sendable {
    public let items: [MediaSegmentDto]?
    public let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

/// DTO for chapter info embedded in BaseItemDto.
public struct ChapterInfoDto: Codable, Sendable {
    public let startPositionTicks: Int64?
    public let name: String?
    public let imagePath: String?
    public let imageTag: String?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case imagePath = "ImagePath"
        case imageTag = "ImageTag"
    }
}
