import Foundation
import GRDB
import Models

/// GRDB record for the `servers` table.
/// Maps between database rows and the domain `ServerConnection` type.
struct ServerRecord: Codable, Sendable {
    var id: String
    var name: String
    var url: String
    var userId: String
    var serverType: String
    var createdAt: Date

    /// Convert from a domain model.
    init(from connection: ServerConnection) {
        self.id = connection.id.uuidString
        self.name = connection.name
        self.url = connection.url.absoluteString
        self.userId = connection.userId
        self.serverType = connection.serverType.rawValue
        self.createdAt = Date()
    }

    /// Convert to a domain model.
    func toServerConnection() -> ServerConnection? {
        guard
            let uuid = UUID(uuidString: id),
            let serverURL = URL(string: url),
            let type = ServerType(rawValue: serverType)
        else {
            return nil
        }
        return ServerConnection(
            id: uuid,
            name: name,
            url: serverURL,
            userId: userId,
            serverType: type
        )
    }
}

// MARK: - GRDB Conformances

extension ServerRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "servers"
}
