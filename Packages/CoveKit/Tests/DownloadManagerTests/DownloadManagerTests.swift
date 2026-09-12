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


/// Tests for keeping access tokens out of persisted download URLs.
final class DownloadURLCredentialTests: XCTestCase {

    // MARK: - Stripping

    func testLegacyAPIKeyIsStripped() {
        XCTAssertEqual(
            DownloadManagerService.credentialFreeURL(
                from: "https://example.com/Items/i1/Download?api_key=tok"),
            "https://example.com/Items/i1/Download")
    }

    func testModernApiKeyIsStripped() {
        XCTAssertEqual(
            DownloadManagerService.credentialFreeURL(
                from: "https://example.com/Items/i1/Download?ApiKey=tok"),
            "https://example.com/Items/i1/Download")
    }

    func testOtherParametersSurviveStripping() throws {
        let stripped = DownloadManagerService.credentialFreeURL(
            from: "https://example.com/Videos/v1/stream?static=false&api_key=tok&container=mp4")

        let items = try XCTUnwrap(
            URLComponents(string: stripped)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["static", "container"])
        XCTAssertEqual(items.first { $0.name == "container" }?.value, "mp4")
    }

    func testURLWithoutCredentialsIsUnchanged() {
        let original = "https://example.com/Items/i1/Download?static=true"
        XCTAssertEqual(DownloadManagerService.credentialFreeURL(from: original), original)
    }

    /// `isResumable` reads `static=false` out of the stored URL, so stripping the
    /// token must not disturb it.
    func testStrippingPreservesResumabilityMarker() {
        let stripped = DownloadManagerService.credentialFreeURL(
            from: "https://example.com/Videos/v1/stream?static=false&ApiKey=tok")
        XCTAssertTrue(stripped.contains("static=false"))
    }
}

/// Regression tests for CWE-22: a media server chooses `BaseItemDto.Id`, and it
/// used to reach the file system unfiltered.
final class DownloadStoragePathTraversalTests: XCTestCase {

    private let storage = DownloadStorage.shared

    // MARK: - Component sanitising

    func testTraversalSequencesCannotSurviveAsAComponent() {
        for hostile in ["..", ".", "../..", "../../../com.nikolajjsj.cove", "a/b", "a\\b", "\0"] {
            let safe = DownloadStorage.safeComponent(hostile)
            XCTAssertFalse(safe.contains("/"), "\(hostile) kept a separator")
            XCTAssertFalse(safe.contains("\\"), "\(hostile) kept a separator")
            XCTAssertNotEqual(safe, "..")
            XCTAssertNotEqual(safe, ".")
        }
    }

    /// Real Jellyfin ids must be untouched, or every existing download relocates.
    func testLegitimateGUIDsPassThroughUnchanged() {
        for id in ["a1b2c3d4e5f60718293a4b5c6d7e8f90", "A1B2C3D4-E5F6-0718-293A-4B5C6D7E8F90"] {
            XCTAssertEqual(DownloadStorage.safeComponent(id), id)
        }
    }

    func testSanitisingIsDeterministic() {
        XCTAssertEqual(
            DownloadStorage.safeComponent("../../evil"),
            DownloadStorage.safeComponent("../../evil"))
    }

    // MARK: - The sinks

    /// The original attack: an id three levels of `..` up reaches the directory
    /// holding cove.db, which `deleteFiles` would then recursively remove.
    func testHostileItemIDCannotEscapeTheDownloadsTree() {
        let dir = storage.itemDirectory(
            serverId: UUID().uuidString,
            mediaType: .movie,
            itemId: ItemID("../../../com.nikolajjsj.cove"))

        XCTAssertTrue(storage.isContained(dir), "escaped to \(dir.standardizedFileURL.path)")
        XCTAssertFalse(dir.path.contains(".."))
    }

    func testHostileServerIDCannotEscapeTheDownloadsTree() {
        XCTAssertTrue(storage.isContained(storage.serverDirectory(serverId: "../../../etc")))
    }

    func testHostileRelativePathCannotEscapeOnResolve() {
        let url = storage.resolveAbsoluteURL(relativePath: "../../../com.nikolajjsj.cove/cove.db")
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(
            storage.downloadsDirectory.standardizedFileURL.path))
    }

    /// The persisted path and the URL used to write must agree, or completed
    /// downloads become unreadable.
    func testRelativePathMatchesTheDirectoryActuallyUsed() {
        let item = Self.makeItem(itemId: "../../../evil")
        let relative = storage.relativeFilePath(for: item, fileExtension: "mp4")
        XCTAssertEqual(
            storage.resolveAbsoluteURL(relativePath: relative).standardizedFileURL.path,
            storage.mediaFileURL(for: item, fileExtension: "mp4").standardizedFileURL.path)
    }

    func testContainmentRejectsASiblingWithTheSamePrefix() {
        let sibling = storage.downloadsDirectory
            .deletingLastPathComponent()
            .appending(path: "Downloads-evil")
        XCTAssertFalse(storage.isContained(sibling))
    }

    private static func makeItem(itemId: String) -> DownloadItem {
        DownloadItem(
            id: UUID().uuidString,
            itemId: ItemID(itemId),
            serverId: UUID().uuidString,
            title: "Title",
            mediaType: .movie,
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

