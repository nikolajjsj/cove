import Models
import XCTest

@testable import DownloadManager

/// Tests for the pure, file-system-layout parts of the download engine.
///
/// `DownloadManagerService` itself needs a live GRDB database, so it is covered
/// by the integration tests in `PersistenceTests` rather than here.
final class DownloadStorageTests: XCTestCase {

    private let storage = DownloadStorage.shared

    // MARK: - Path Layout

    func testItemDirectoryFollowsServerTypeItemLayout() {
        let dir = storage.itemDirectory(
            serverId: "server-1", mediaType: .episode, itemId: ItemID("item-9"))

        XCTAssertTrue(
            dir.path.hasSuffix("Downloads/server-1/\(MediaType.episode.rawValue)/item-9"),
            "Unexpected layout: \(dir.path)")
    }

    func testRelativeFilePathAndResolveAreInverses() {
        let item = Self.makeItem(serverId: "server-1", mediaType: .movie, itemId: "item-9")
        let relative = storage.relativeFilePath(for: item, fileExtension: "mp4")

        XCTAssertEqual(relative, "server-1/\(MediaType.movie.rawValue)/item-9/media.mp4")
        XCTAssertEqual(
            storage.resolveAbsoluteURL(relativePath: relative).path,
            storage.mediaFileURL(for: item, fileExtension: "mp4").path)
    }

    func testServerDirectoryIsTheParentOfEveryItemDirectory() {
        let server = storage.serverDirectory(serverId: "server-1")
        let item = storage.itemDirectory(
            serverId: "server-1", mediaType: .track, itemId: ItemID("t1"))

        XCTAssertTrue(item.path.hasPrefix(server.path + "/"))
    }

    // MARK: - File Extension Resolution

    func testFileExtensionPrefersContentDisposition() throws {
        let response = try Self.makeResponse(headers: [
            "Content-Disposition": #"attachment; filename="Episode.mkv""#,
            "Content-Type": "video/mp4",
        ])
        XCTAssertEqual(storage.fileExtension(from: response), "mkv")
    }

    func testFileExtensionFallsBackToMimeType() throws {
        let response = try Self.makeResponse(headers: ["Content-Type": "video/mp4"])
        XCTAssertEqual(storage.fileExtension(from: response), "mp4")
    }

    /// `application/octet-stream` carries no format information, so it must not be
    /// mapped to an extension — the caller is expected to fail the download instead
    /// of writing a file AVPlayer cannot open.
    func testFileExtensionRejectsOpaqueOctetStream() throws {
        let response = try Self.makeResponse(headers: ["Content-Type": "application/octet-stream"])
        XCTAssertNil(storage.fileExtension(from: response))
    }

    func testFileExtensionIsNilWithoutUsableHeaders() throws {
        let response = try Self.makeResponse(headers: [:])
        XCTAssertNil(storage.fileExtension(from: response))
    }

    // MARK: - Helpers

    private static func makeResponse(headers: [String: String]) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/Items/item-9/Download")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers))
    }

    private static func makeItem(
        serverId: String, mediaType: MediaType, itemId: String
    ) -> DownloadItem {
        DownloadItem(
            id: UUID().uuidString,
            itemId: ItemID(itemId),
            serverId: serverId,
            title: "Title",
            mediaType: mediaType,
            state: .completed,
            progress: 1,
            totalBytes: 1,
            downloadedBytes: 1,
            localFilePath: nil,
            remoteURL: "https://example.com/stream",
            parentId: nil,
            artworkURL: nil,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: Date()
        )
    }
}

