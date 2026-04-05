import Foundation

public struct ServerConnection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let userId: String
    public let serverType: ServerType

    public init(id: UUID = UUID(), name: String, url: URL, userId: String, serverType: ServerType) {
        self.id = id
        self.name = name
        self.url = url
        self.userId = userId
        self.serverType = serverType
    }
}
