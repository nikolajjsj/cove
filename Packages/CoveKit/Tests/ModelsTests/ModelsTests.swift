import Testing

@testable import Models

@Test func itemIDCreation() {
    let id = ItemID("test-123")
    #expect(id.rawValue == "test-123")
    #expect(id.description == "test-123")
}

@Test func itemIDEquality() {
    let id1 = ItemID("abc")
    let id2 = ItemID("abc")
    let id3 = ItemID("xyz")
    #expect(id1 == id2)
    #expect(id1 != id3)
}

@Test func mediaItemCodable() throws {
    let item = MediaItem(
        id: ItemID("item-1"),
        title: "Test Movie",
        overview: "A test movie",
        mediaType: .movie,
        dateAdded: nil,
        userData: UserData(isFavorite: true, playbackPosition: 120, playCount: 1, isPlayed: false)
    )

    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(MediaItem.self, from: data)

    #expect(decoded.id == item.id)
    #expect(decoded.title == item.title)
    #expect(decoded.mediaType == .movie)
    #expect(decoded.userData?.isFavorite == true)
    #expect(decoded.userData?.playbackPosition == 120)
}

@Test func serverConnectionCodable() throws {
    let connection = ServerConnection(
        name: "My Server",
        url: URL(string: "https://jellyfin.example.com")!,
        userId: "user-123",
        serverType: .jellyfin
    )

    let data = try JSONEncoder().encode(connection)
    let decoded = try JSONDecoder().decode(ServerConnection.self, from: data)

    #expect(decoded.name == "My Server")
    #expect(decoded.serverType == .jellyfin)
    #expect(decoded.userId == "user-123")
}

@Test func appErrorDescriptions() {
    let error = AppError.networkUnavailable
    #expect(error.localizedDescription.contains("network"))

    let authError = AppError.authFailed(reason: "bad password")
    #expect(authError.localizedDescription.contains("bad password"))
}
