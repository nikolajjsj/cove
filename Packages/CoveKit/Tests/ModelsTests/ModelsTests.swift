import XCTest

@testable import Models

final class ModelsTests: XCTestCase {
    func testItemIDCreation() {
        let id = ItemID("test-123")
        XCTAssertEqual(id.rawValue, "test-123")
        XCTAssertEqual(id.description, "test-123")
    }

    func testItemIDEquality() {
        let id1 = ItemID("abc")
        let id2 = ItemID("abc")
        let id3 = ItemID("xyz")
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    func testMediaItemCodable() throws {
        let item = MediaItem(
            id: ItemID("item-1"),
            title: "Test Movie",
            overview: "A test movie",
            mediaType: .movie,
            dateAdded: nil,
            userData: UserData(
                isFavorite: true, playbackPosition: 120, playCount: 1, isPlayed: false)
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.title, item.title)
        XCTAssertEqual(decoded.mediaType, .movie)
        XCTAssertEqual(decoded.userData?.isFavorite, true)
        XCTAssertEqual(decoded.userData?.playbackPosition, 120)
    }

    func testServerConnectionCodable() throws {
        let connection = ServerConnection(
            name: "My Server",
            url: URL(string: "https://jellyfin.example.com")!,
            userId: "user-123",
            serverType: .jellyfin
        )

        let data = try JSONEncoder().encode(connection)
        let decoded = try JSONDecoder().decode(ServerConnection.self, from: data)

        XCTAssertEqual(decoded.name, "My Server")
        XCTAssertEqual(decoded.serverType, .jellyfin)
        XCTAssertEqual(decoded.userId, "user-123")
    }

    func testAppErrorDescriptions() {
        let error = AppError.networkUnavailable
        XCTAssertTrue(
            error.localizedDescription.contains("network")
                || error.localizedDescription.contains("No"))

        let authError = AppError.authFailed(reason: "bad password")
        XCTAssertTrue(authError.localizedDescription.contains("bad password"))
    }
}
