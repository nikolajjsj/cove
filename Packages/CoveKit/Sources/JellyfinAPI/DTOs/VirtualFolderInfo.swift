import Foundation

/// Response DTO for `GET /Library/VirtualFolders`
/// The response is an array of these objects.
public struct VirtualFolderInfo: Codable, Sendable {
    public let name: String?
    public let collectionType: String?
    public let itemId: String?

    public init(
        name: String? = nil,
        collectionType: String? = nil,
        itemId: String? = nil
    ) {
        self.name = name
        self.collectionType = collectionType
        self.itemId = itemId
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case collectionType = "CollectionType"
        case itemId = "ItemId"
    }
}
