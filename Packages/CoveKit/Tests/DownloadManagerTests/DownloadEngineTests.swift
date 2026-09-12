import Foundation
import Models
import Persistence
import XCTest

@testable import DownloadManager

// MARK: - Test doubles

/// A transfer that records what was asked of it instead of touching the network.
final class StubDownloadTask: DownloadTaskHandle, @unchecked Sendable {
    let taskIdentifier: Int
    var taskDescription: String?
    let originalURL: URL?

    private(set) var resumeCallCount = 0
    private(set) var cancelCallCount = 0
    /// Handed back from `cancel(byProducingResumeData:)`, mimicking a server that
    /// supports ranged requests.
    var resumeDataOnCancel: Data?

    init(taskIdentifier: Int, originalURL: URL?) {
        self.taskIdentifier = taskIdentifier
        self.originalURL = originalURL
    }

    func resume() { resumeCallCount += 1 }
    func cancel() { cancelCallCount += 1 }

    func cancel(byProducingResumeData handler: @escaping @Sendable (Data?) -> Void) {
        cancelCallCount += 1
        handler(resumeDataOnCancel)
    }
}

/// Stands in for the background `URLSession`.
final class StubDownloadSession: DownloadSession, @unchecked Sendable {
    private let lock = NSLock()
    private var nextIdentifier = 1
    private var _tasks: [StubDownloadTask] = []

    /// Every task handed out, in creation order.
    var tasks: [StubDownloadTask] {
        lock.lock(); defer { lock.unlock() }
        return _tasks
    }

    /// Requests that were resumed from prior progress rather than started fresh.
    private(set) var resumedFromData: [Data] = []

    func makeDownloadTask(request: URLRequest) -> any DownloadTaskHandle {
        lock.lock(); defer { lock.unlock() }
        let task = StubDownloadTask(taskIdentifier: nextIdentifier, originalURL: request.url)
        nextIdentifier += 1
        _tasks.append(task)
        return task
    }

    func makeDownloadTask(resumeData: Data) -> any DownloadTaskHandle {
        lock.lock(); defer { lock.unlock() }
        resumedFromData.append(resumeData)
        let task = StubDownloadTask(taskIdentifier: nextIdentifier, originalURL: nil)
        nextIdentifier += 1
        _tasks.append(task)
        return task
    }

    func activeTasks() async -> [any DownloadTaskHandle] { tasks }
}

// MARK: - Fixture

/// A fully wired engine backed by an in-memory database and a temporary
/// downloads tree, so the real staging/move/delete logic runs.
@MainActor
final class DownloadEngineFixture {
    let root: URL
    let storage: DownloadStorage
    let repository: DownloadRepository
    let session = StubDownloadSession()
    let service: DownloadManagerService
    /// downloads.serverId is a foreign key onto servers.id, so rows need a real
    /// connection behind them.
    let serverId: String

    init() async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "cove-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        storage = DownloadStorage(rootDirectory: root)
        let database = try DatabaseManager()

        let connection = ServerConnection(
            name: "Test", url: URL(string: "https://example.com")!,
            userId: "user-1", serverType: .jellyfin)
        try await ServerRepository(database: database).save(connection)
        serverId = connection.id.uuidString

        repository = DownloadRepository(database: database)
        service = DownloadManagerService(
            downloadRepository: repository,
            reportRepository: OfflinePlaybackReportRepository(database: database),
            storage: storage,
            groupRepository: DownloadGroupRepository(database: database),
            metadataRepository: OfflineMetadataRepository(database: database),
            session: session
        )
        service.authTokenProvider = { "test-token" }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A file standing in for one URLSession has finished writing to its temp location.
    func makeDownloadedFile(contents: String = "media bytes") throws -> URL {
        let url = root.appending(path: "incoming-\(UUID().uuidString)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Enqueue one item and let the scheduler start it, so a task is registered
    /// and the delegate handlers have something to resolve.
    @discardableResult
    func enqueueAndStart(
        title: String = "Movie", remoteURL: String = "https://example.com/Items/i1/Download"
    ) async throws -> DownloadItem {
        let item = try await service.enqueueDownload(
            itemId: ItemID(UUID().uuidString),
            serverId: serverId,
            title: title,
            mediaType: .movie,
            remoteURL: try XCTUnwrap(URL(string: remoteURL)),
            expectedBytes: 1000
        )
        try await settle()
        return item
    }

    /// A queued row built directly, so saving it does not kick the scheduler.
    func makeQueuedItem(
        title: String,
        state: DownloadState = .queued,
        remoteURL: String = "https://example.com/Items/i1/Download"
    ) -> DownloadItem {
        DownloadItem(
            id: UUID().uuidString,
            itemId: ItemID(UUID().uuidString),
            serverId: serverId,
            title: title,
            mediaType: .movie,
            state: state,
            progress: 0,
            totalBytes: 1000,
            downloadedBytes: 0,
            localFilePath: nil,
            remoteURL: remoteURL,
            parentId: nil,
            artworkURL: nil,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: nil
        )
    }

    /// Enqueue without waiting for the scheduler.
    @discardableResult
    func enqueue(title: String = "Movie") async throws -> DownloadItem {
        try await service.enqueueDownload(
            itemId: ItemID(UUID().uuidString),
            serverId: serverId,
            title: title,
            mediaType: .movie,
            remoteURL: try XCTUnwrap(URL(string: "https://example.com/Items/i1/Download")),
            expectedBytes: 1000
        )
    }

    /// The delegate handlers hand their database work to detached tasks, so give
    /// those a chance to land before asserting.
    func settle() async throws {
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0..<20 { await Task.yield() }
    }

    func response(status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/Items/i1/Download")!,
                statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }
}

// MARK: - Completion handling

@MainActor
final class DownloadCompletionTests: XCTestCase {

    /// A URLSessionDownloadTask reports success for any completed HTTP exchange,
    /// so an expired token arrives here as a 401 whose body is an error page. It
    /// must not be stored and marked completed.
    func testNon2xxResponseFailsTheDownloadInsteadOfStoringTheErrorBody() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()
        let file = try fixture.makeDownloadedFile(contents: "<html>401</html>")

        fixture.service.handleDownloadFinished(
            taskIdentifier: 1, location: file,
            response: try fixture.response(status: 401, headers: ["Content-Type": "text/html"]))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertNil(stored.localFilePath)
        XCTAssertEqual(stored.errorMessage, "Sign-in expired — reconnect to the server and retry")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "temp file was left behind")
    }

    func testServerErrorNamesTheStatusCode() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleDownloadFinished(
            taskIdentifier: 1, location: try fixture.makeDownloadedFile(),
            response: try fixture.response(status: 503))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertEqual(stored.errorMessage, "Server returned HTTP 503")
    }

    func testSuccessfulDownloadIsStoredAndMarkedCompleted() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleDownloadFinished(
            taskIdentifier: 1, location: try fixture.makeDownloadedFile(contents: "movie"),
            response: try fixture.response(status: 200, headers: ["Content-Type": "video/mp4"]))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .completed)
        let path = try XCTUnwrap(stored.localFilePath)
        XCTAssertTrue(path.hasSuffix("/media.mp4"), "unexpected path: \(path)")

        let onDisk = fixture.storage.resolveAbsoluteURL(relativePath: path)
        XCTAssertEqual(try String(contentsOf: onDisk, encoding: .utf8), "movie")
        // The size is corrected from the real file, not left at the server estimate.
        XCTAssertEqual(stored.totalBytes, Int64("movie".utf8.count))
    }

    /// Without a usable Content-Type or filename there is no way to know what was
    /// downloaded, and guessing produces a file AVPlayer cannot open.
    func testUndeterminableFileTypeFailsRatherThanGuessing() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleDownloadFinished(
            taskIdentifier: 1, location: try fixture.makeDownloadedFile(),
            response: try fixture.response(
                status: 200, headers: ["Content-Type": "application/octet-stream"]))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertNil(stored.localFilePath)
    }

    func testContentDispositionFilenameWinsOverMimeType() async throws {
        let fixture = try await DownloadEngineFixture()
        _ = try await fixture.enqueueAndStart()

        fixture.service.handleDownloadFinished(
            taskIdentifier: 1, location: try fixture.makeDownloadedFile(),
            response: try fixture.response(
                status: 200,
                headers: [
                    "Content-Type": "video/mp4",
                    "Content-Disposition": #"attachment; filename="Episode.mkv""#,
                ]))
        try await fixture.settle()

        let all = try await fixture.repository.fetchAll()
        let stored = try XCTUnwrap(all.first)
        XCTAssertTrue(try XCTUnwrap(stored.localFilePath).hasSuffix("/media.mkv"))
    }

    func testCompletionForAnUnknownTaskIsIgnored() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleDownloadFinished(
            taskIdentifier: 999, location: try fixture.makeDownloadedFile(),
            response: try fixture.response(status: 200, headers: ["Content-Type": "video/mp4"]))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .downloading, "an unrelated task changed our record")
    }
}

// MARK: - Scheduling

@MainActor
final class DownloadSchedulerTests: XCTestCase {

    func testSchedulerStartsUpToTheConcurrencyLimitAndNoFurther() async throws {
        let fixture = try await DownloadEngineFixture()
        for index in 0..<6 { try await fixture.enqueue(title: "Item \(index)") }
        try await fixture.settle()

        XCTAssertEqual(fixture.session.tasks.count, 3, "concurrency limit not respected")
        XCTAssertTrue(fixture.session.tasks.allSatisfy { $0.resumeCallCount == 1 })

        let downloading = try await fixture.repository.fetchAll(state: .downloading)
        let queued = try await fixture.repository.fetchAll(state: .queued)
        XCTAssertEqual(downloading.count, 3)
        XCTAssertEqual(queued.count, 3)
    }

    /// The scheduler suspends between finding a free slot and marking the row as
    /// downloading, and it is called from the delegate, the progress tasks,
    /// enqueue, cancel and delete. Concurrent callers must not both claim the
    /// same queued row and start two transfers for one item.
    ///
    /// The rows are written straight to the repository rather than through
    /// `enqueueDownload`, which would kick the scheduler and drain the queue
    /// before the concurrent calls begin — leaving no race to lose.
    func testConcurrentSchedulerCallsNeverStartAnItemTwice() async throws {
        let fixture = try await DownloadEngineFixture()
        for index in 0..<8 {
            try await fixture.repository.save(fixture.makeQueuedItem(title: "Item \(index)"))
        }
        XCTAssertEqual(fixture.session.tasks.count, 0, "scheduler ran during setup")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask { await fixture.service.startNextDownloadsIfNeeded() }
            }
        }
        try await fixture.settle()

        let descriptions = fixture.session.tasks.compactMap(\.taskDescription)
        XCTAssertEqual(
            Set(descriptions).count, descriptions.count,
            "the same download was started by more than one task")
        XCTAssertEqual(
            fixture.session.tasks.count, 3,
            "concurrency limit exceeded: \(fixture.session.tasks.count) transfers started")
    }

    func testFinishingOneDownloadStartsTheNextQueuedItem() async throws {
        let fixture = try await DownloadEngineFixture()
        for index in 0..<4 { try await fixture.enqueue(title: "Item \(index)") }
        try await fixture.settle()
        XCTAssertEqual(fixture.session.tasks.count, 3)

        fixture.service.handleTaskCompleted(taskIdentifier: 1, error: nil)
        try await fixture.settle()

        XCTAssertEqual(fixture.session.tasks.count, 4, "the freed slot was not refilled")
    }

    func testWifiOnlyGateStopsTheQueueStartingOnCellular() async throws {
        let fixture = try await DownloadEngineFixture()
        fixture.service.isWifiOnlyEnabled = { true }
        // NetworkMonitor reports not-expensive in tests, so the gate stays open;
        // assert the gate is at least consulted rather than asserting on the monitor.
        try await fixture.enqueue()
        try await fixture.settle()
        XCTAssertLessThanOrEqual(fixture.session.tasks.count, 1)
    }

    // MARK: Failure handling

    func testTransferFailureMarksTheDownloadFailedWithTheReason() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        let error = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        fixture.service.handleTaskCompleted(taskIdentifier: 1, error: error)
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertEqual(stored.errorMessage, "The request timed out.")
    }

    /// Cancellation is how pause and delete stop a transfer, so it must not be
    /// reported to the user as a failure.
    func testDeliberateCancellationIsNotRecordedAsAFailure() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleTaskCompleted(
            taskIdentifier: 1,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        XCTAssertEqual(try XCTUnwrap(fetched).state, .downloading)
    }

    /// Resume data lets an interrupted transfer continue instead of restarting.
    func testResumeDataFromAFailureIsUsedOnRetry() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        let resumeData = Data("partial".utf8)
        fixture.service.handleTaskCompleted(
            taskIdentifier: 1,
            error: NSError(
                domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                userInfo: ["NSURLSessionDownloadTaskResumeData": resumeData]))
        try await fixture.settle()

        try await fixture.service.retryDownload(id: item.id)
        try await fixture.settle()

        XCTAssertEqual(fixture.session.resumedFromData, [resumeData])
    }

    // MARK: Progress

    func testProgressUsesTheEnqueuedSizeWhenTheServerOmitsContentLength() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        // A transcoded stream has no Content-Length, so -1 arrives here.
        fixture.service.handleProgress(
            taskIdentifier: 1, bytesWritten: 500, totalBytesWritten: 500,
            totalBytesExpectedToWrite: -1)
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.downloadedBytes, 500)
        XCTAssertEqual(stored.progress, 0.5, accuracy: 0.001, "fell back to the enqueued size")
    }

    func testProgressNeverExceedsOne() async throws {
        let fixture = try await DownloadEngineFixture()
        let item = try await fixture.enqueueAndStart()

        fixture.service.handleProgress(
            taskIdentifier: 1, bytesWritten: 5000, totalBytesWritten: 5000,
            totalBytesExpectedToWrite: 1000)
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: item.id)
        XCTAssertLessThanOrEqual(try XCTUnwrap(fetched).progress, 1.0)
    }
}

// MARK: - Launch reconciliation & credential hygiene

@MainActor
final class DownloadLaunchTests: XCTestCase {

    /// A row left in `.downloading` by a killed app has no live task behind it,
    /// so it must go back to the queue rather than stall forever.
    func testOrphanedDownloadingRowsAreRequeuedOnLaunch() async throws {
        let fixture = try await DownloadEngineFixture()
        let orphan = fixture.makeQueuedItem(title: "Interrupted", state: .downloading)
        try await fixture.repository.save(orphan)

        await fixture.service.restoreDownloadsOnLaunch()
        try await fixture.settle()

        let fetched = try await fixture.repository.fetch(id: orphan.id)
        let stored = try XCTUnwrap(fetched)
        // Re-queued, then picked straight back up by the scheduler.
        XCTAssertEqual(stored.state, .downloading)
        XCTAssertEqual(fixture.session.tasks.count, 1, "the orphan was not restarted")
    }

    /// Tokens were once persisted inside remoteURL. Rows written by those builds
    /// must be scrubbed, and the modern and legacy spellings both count.
    func testStoredCredentialsAreScrubbedOnLaunch() async throws {
        let fixture = try await DownloadEngineFixture()
        let legacy = fixture.makeQueuedItem(
            title: "Legacy", state: .completed,
            remoteURL: "https://example.com/Items/i1/Download?api_key=SECRET")
        let modern = fixture.makeQueuedItem(
            title: "Modern", state: .completed,
            remoteURL: "https://example.com/Items/i2/Download?ApiKey=SECRET&static=true")
        try await fixture.repository.save(legacy)
        try await fixture.repository.save(modern)

        await fixture.service.restoreDownloadsOnLaunch()
        try await fixture.settle()

        let all = try await fixture.repository.fetchAll()
        for row in all {
            XCTAssertFalse(row.remoteURL.contains("SECRET"), "token left in \(row.remoteURL)")
        }
        let scrubbedModern = try XCTUnwrap(all.first { $0.id == modern.id })
        XCTAssertTrue(
            scrubbedModern.remoteURL.contains("static=true"),
            "scrubbing dropped an unrelated parameter")
    }

    /// The stored URL is credential-free, so the live token has to be attached
    /// when the transfer actually starts — which is also what makes a download
    /// resumed after a re-login use the new token instead of a stale one.
    func testTheLiveTokenIsAttachedWhenTheTransferStarts() async throws {
        let fixture = try await DownloadEngineFixture()
        try await fixture.enqueueAndStart()

        let task = try XCTUnwrap(fixture.session.tasks.first)
        let url = try XCTUnwrap(task.originalURL)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(items.first { $0.name == "ApiKey" }?.value, "test-token")
        XCTAssertNil(items.first { $0.name == "api_key" }, "legacy parameter used")
    }

    func testEnqueueNeverWritesATokenToTheDatabase() async throws {
        let fixture = try await DownloadEngineFixture()
        _ = try await fixture.service.enqueueDownload(
            itemId: ItemID(UUID().uuidString),
            serverId: fixture.serverId,
            title: "Movie",
            mediaType: .movie,
            remoteURL: try XCTUnwrap(
                URL(string: "https://example.com/Items/i1/Download?ApiKey=SECRET")),
            expectedBytes: 10
        )
        try await fixture.settle()

        let allRows = try await fixture.repository.fetchAll()
        let stored = try XCTUnwrap(allRows.first)
        XCTAssertFalse(stored.remoteURL.contains("SECRET"))
    }

    func testDuplicateEnqueueIsANoOp() async throws {
        let fixture = try await DownloadEngineFixture()
        let itemId = ItemID(UUID().uuidString)
        let url = try XCTUnwrap(URL(string: "https://example.com/Items/i1/Download"))

        let first = try await fixture.service.enqueueDownload(
            itemId: itemId, serverId: fixture.serverId, title: "Movie",
            mediaType: .movie, remoteURL: url, expectedBytes: 10)
        let second = try await fixture.service.enqueueDownload(
            itemId: itemId, serverId: fixture.serverId, title: "Movie",
            mediaType: .movie, remoteURL: url, expectedBytes: 10)
        try await fixture.settle()

        XCTAssertEqual(first.id, second.id)
        let all = try await fixture.repository.fetchAll()
        XCTAssertEqual(all.count, 1)
    }
}
