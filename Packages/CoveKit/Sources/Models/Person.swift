import Foundation

/// A person associated with a media item (actor, director, writer, etc.).
public struct Person: Identifiable, Hashable, Codable, Sendable {
    public var uniqueID: String {
        "\(id)-\(role)"
    }
    
    public let id: ItemID
    public let name: String
    public let role: String?
    public let type: String?
    public let imageURL: URL?

    public init(
        id: ItemID,
        name: String,
        role: String? = nil,
        type: String? = nil,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.imageURL = imageURL
    }
}

public typealias PersonID = ItemID
