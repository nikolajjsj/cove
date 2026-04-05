import GRDB
import XCTest

@testable import Models
@testable import Persistence

final class PersistenceTests: XCTestCase {
    var dbManager: DatabaseManager!
    var serverRepo: ServerRepository!

    override func setUp() async throws {
        dbManager = try DatabaseManager()  // in-memory
        serverRepo = ServerRepository(database: dbManager)
    }

    func testDatabaseManagerInitialization() {
        XCTAssertNotNil(dbManager)
        XCTAssertNotNil(dbManager.dbWriter)
    }

    func testSaveAndFetchServer() async throws {
        let connection = ServerConnection(
            name: "Test Server",
            url: URL(string: "https://jellyfin.example.com")!,
            userId: "user-123",
            serverType: .jellyfin
        )

        try await serverRepo.save(connection)

        let fetched = try await serverRepo.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test Server")
        XCTAssertEqual(fetched.first?.userId, "user-123")
        XCTAssertEqual(fetched.first?.serverType, .jellyfin)
        XCTAssertEqual(fetched.first?.id, connection.id)
    }

    func testFetchByID() async throws {
        let connection = ServerConnection(
            name: "My Server",
            url: URL(string: "https://jf.local:8096")!,
            userId: "user-456",
            serverType: .jellyfin
        )

        try await serverRepo.save(connection)

        let found = try await serverRepo.fetch(id: connection.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "My Server")

        let notFound = try await serverRepo.fetch(id: UUID())
        XCTAssertNil(notFound)
    }

    func testDeleteServer() async throws {
        let connection = ServerConnection(
            name: "Delete Me",
            url: URL(string: "https://deleteme.local")!,
            userId: "user-789",
            serverType: .jellyfin
        )

        try await serverRepo.save(connection)
        var all = try await serverRepo.fetchAll()
        XCTAssertEqual(all.count, 1)

        try await serverRepo.delete(id: connection.id)
        all = try await serverRepo.fetchAll()
        XCTAssertEqual(all.count, 0)
    }

    func testMultipleServers() async throws {
        let server1 = ServerConnection(
            name: "Server 1",
            url: URL(string: "https://server1.local")!,
            userId: "user-a",
            serverType: .jellyfin
        )
        let server2 = ServerConnection(
            name: "Server 2",
            url: URL(string: "https://server2.local")!,
            userId: "user-b",
            serverType: .jellyfin
        )

        try await serverRepo.save(server1)
        try await serverRepo.save(server2)

        let all = try await serverRepo.fetchAll()
        XCTAssertEqual(all.count, 2)
    }

    func testDeleteAll() async throws {
        let server1 = ServerConnection(
            name: "S1", url: URL(string: "https://s1.local")!, userId: "u1", serverType: .jellyfin
        )
        let server2 = ServerConnection(
            name: "S2", url: URL(string: "https://s2.local")!, userId: "u2", serverType: .jellyfin
        )

        try await serverRepo.save(server1)
        try await serverRepo.save(server2)
        try await serverRepo.deleteAll()

        let all = try await serverRepo.fetchAll()
        XCTAssertEqual(all.count, 0)
    }
}
