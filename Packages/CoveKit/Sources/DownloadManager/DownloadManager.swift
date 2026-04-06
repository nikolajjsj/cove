import Foundation
import Models
import Persistence
import UserNotifications
import os

// MARK: - DownloadManagerService

/// The core download engine for Cove.
///
/// `DownloadManagerService` coordinates background downloads using a
/// `URLSession` with a background configuration so that transfers continue
/// even when the app is suspended. It persists download state in GRDB via
/// `DownloadRepository` and manages the on-disk file layout through
/// `DownloadStorage`.
///
/// ## Concurrency Model
///
/// Internal mutable state (task-to-ID mappings, resume-data cache, active
/// download count) is protected by an `OSAllocatedUnfairLock` wrapping a
/// single `State` struct. The class is marked `@unchecked Sendable` because
/// the `URLSessionDownloadDelegate` callback pattern pre-dates Swift
/// concurrency and cannot be formally proven `Sendable` by the compiler.
///
/// ## State Machine
///
///     queued → downloading → completed
///                  │
///                  ├──→ paused → downloading (resume)
///                  │
///                  └──→ failed → downloading (retry)
///
public final class DownloadManagerService: @unchecked Sendable {

    // MARK: - Constants

    /// Background session identifier. Must be stable across app launches.
    private static let backgroundSessionIdentifier =
        "com.nikolajjsj.jellyfin.backgroundDownloads"

    /// Maximum number of downloads that may be actively transferring at once.
    private static let maxConcurrentDownloads = 3

    /// The key used by `URLSession` to store resume data in the error's userInfo.
    private static let resumeDataKey = "NSURLSessionDownloadTaskResumeData"

    // MARK: - Dependencies

    private let downloadRepository: DownloadRepository
    private let reportRepository: OfflinePlaybackReportRepository
    private let storage: DownloadStorage
    private let groupRepository: DownloadGroupRepository?
    private let metadataRepository: OfflineMetadataRepository?

    /// Closure that returns whether downloads should be WiFi-only.
    /// Injected by the app layer since the DownloadManager module doesn't depend on Defaults.
    public var isWifiOnlyEnabled: @Sendable () -> Bool = { false }
    private let logger = Logger(
        subsystem: "com.nikolajjsj.jellyfin", category: "DownloadManager")

    // MARK: - URLSession & Delegate

    /// The background URL session. Created in `init` to wire up the delegate.
    private let urlSession: URLSession

    /// The delegate object (must be kept alive for the lifetime of the session).
    private let sessionDelegate: SessionDelegate

    // MARK: - Protected Mutable State

    /// All mutable state that must be accessed under the lock.
    private struct State {
        /// Maps active `URLSessionDownloadTask.taskIdentifier` → `DownloadItem.id`.
        var taskToDownloadID: [Int: String] = [:]
        /// Cached resume data, keyed by `DownloadItem.id`.
        var resumeDataCache: [String: Data] = [:]
        /// Number of downloads currently in the `.downloading` state with an active task.
        var activeDownloadCount: Int = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    // MARK: - Init

    /// Creates a new download manager.
    ///
    /// - Parameters:
    ///   - downloadRepository: Repository for persisting download records.
    ///   - reportRepository: Repository for offline playback reports (retained
    ///     for future integration but not directly used by the download engine).
    ///   - storage: File-system helper. Defaults to `.shared`.
    public init(
        downloadRepository: DownloadRepository,
        reportRepository: OfflinePlaybackReportRepository,
        storage: DownloadStorage = .shared,
        groupRepository: DownloadGroupRepository? = nil,
        metadataRepository: OfflineMetadataRepository? = nil
    ) {
        self.downloadRepository = downloadRepository
        self.reportRepository = reportRepository
        self.storage = storage
        self.groupRepository = groupRepository
        self.metadataRepository = metadataRepository
        self.state = OSAllocatedUnfairLock(initialState: State())

        // Create the delegate first — we need it for the session.
        let delegate = SessionDelegate()
        self.sessionDelegate = delegate

        // Background configuration keeps transfers alive when the app is suspended.
        let config = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        // The delegate queue MUST be serial so callbacks arrive in order.
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        delegateQueue.name = "com.nikolajjsj.jellyfin.DownloadManagerDelegateQueue"

        self.urlSession = URLSession(
            configuration: config, delegate: delegate, delegateQueue: delegateQueue)

        // Wire the delegate back to this service.
        delegate.service = self
    }

    // MARK: - Public API — Enqueue

    /// Enqueue a new download.
    ///
    /// If the item is already in the database the existing record is returned
    /// immediately (duplicate enqueue is a no-op).
    ///
    /// - Returns: The `DownloadItem` representing the queued download.
    @discardableResult
    public func enqueueDownload(
        itemId: ItemID,
        serverId: String,
        title: String,
        mediaType: MediaType,
        remoteURL: URL,
        parentId: ItemID? = nil,
        artworkURL: URL? = nil
    ) async throws -> DownloadItem {
        // Check for duplicates
        if let existing = try await downloadRepository.fetch(
            itemId: itemId, serverId: serverId)
        {
            logger.info(
                "Download already exists for \(itemId.rawValue): state=\(existing.state.rawValue)")
            return existing
        }

        // Check disk space — require at least 100 MB free
        let available = (try? storage.availableDiskSpace()) ?? Int64.max
        if available < 100 * 1024 * 1024 {
            throw AppError.storageFull
        }

        let item = DownloadItem(
            id: UUID().uuidString,
            itemId: itemId,
            serverId: serverId,
            title: title,
            mediaType: mediaType,
            state: .queued,
            progress: 0,
            totalBytes: 0,
            downloadedBytes: 0,
            localFilePath: nil,
            remoteURL: remoteURL.absoluteString,
            parentId: parentId,
            artworkURL: artworkURL?.absoluteString,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: nil
        )

        try await downloadRepository.save(item)
        logger.info("Enqueued download: \(title) [\(item.id)]")

        // Attempt to start immediately if under the concurrency limit
        await startNextDownloadsIfNeeded()

        return item
    }

    // MARK: - Public API — Batch Enqueue

    /// Enqueue all tracks in an album as a download group.
    ///
    /// Creates a `DownloadGroup` for the album, saves metadata for the album and all tracks,
    /// and enqueues each track sorted by disc/track number.
    ///
    /// - Parameters:
    ///   - albumItemId: The album's Jellyfin item ID.
    ///   - tracks: The tracks to download, as `(itemId, title, remoteURL)` tuples.
    ///   - serverId: The server connection UUID string.
    ///   - groupTitle: Display title for the group (album name).
    /// - Returns: The created `DownloadGroup`.
    @discardableResult
    public func enqueueAlbum(
        albumItemId: ItemID,
        tracks: [(itemId: ItemID, title: String, remoteURL: URL)],
        serverId: String,
        groupTitle: String
    ) async throws -> DownloadGroup {
        // Create or fetch existing group
        let group: DownloadGroup
        if let existing = try await groupRepository?.fetch(itemId: albumItemId, serverId: serverId)
        {
            group = existing
        } else {
            group = DownloadGroup(
                itemId: albumItemId,
                serverId: serverId,
                mediaType: .album,
                title: groupTitle
            )
            try await groupRepository?.save(group)
        }

        // Enqueue each track with the group ID
        for track in tracks {
            // Skip if already enqueued
            if let existing = try await downloadRepository.fetch(
                itemId: track.itemId, serverId: serverId)
            {
                logger.info(
                    "Track \(track.itemId.rawValue) already exists: state=\(existing.state.rawValue)"
                )
                continue
            }

            let item = DownloadItem(
                id: UUID().uuidString,
                itemId: track.itemId,
                serverId: serverId,
                title: track.title,
                mediaType: .track,
                state: .queued,
                progress: 0,
                totalBytes: 0,
                downloadedBytes: 0,
                localFilePath: nil,
                remoteURL: track.remoteURL.absoluteString,
                parentId: albumItemId,
                groupId: group.id,
                artworkURL: nil,
                errorMessage: nil,
                createdAt: Date(),
                completedAt: nil
            )
            try await downloadRepository.save(item)
        }

        logger.info(
            "Enqueued \(tracks.count) tracks for album '\(groupTitle)' [group: \(group.id)]")
        await startNextDownloadsIfNeeded()
        return group
    }

    /// Enqueue all episodes in a season as a download group.
    ///
    /// - Parameters:
    ///   - seasonItemId: The season's Jellyfin item ID.
    ///   - seriesItemId: The series' Jellyfin item ID (used as parentId on each episode).
    ///   - episodes: The episodes to download as `(itemId, title, remoteURL)` tuples.
    ///   - serverId: The server connection UUID string.
    ///   - groupTitle: Display title for the group (e.g., "Season 2").
    /// - Returns: The created `DownloadGroup`.
    @discardableResult
    public func enqueueSeason(
        seasonItemId: ItemID,
        seriesItemId: ItemID,
        episodes: [(itemId: ItemID, title: String, remoteURL: URL)],
        serverId: String,
        groupTitle: String
    ) async throws -> DownloadGroup {
        // Create or fetch existing group
        let group: DownloadGroup
        if let existing = try await groupRepository?.fetch(itemId: seasonItemId, serverId: serverId)
        {
            group = existing
        } else {
            group = DownloadGroup(
                itemId: seasonItemId,
                serverId: serverId,
                mediaType: .season,
                title: groupTitle
            )
            try await groupRepository?.save(group)
        }

        // Enqueue each episode with the group ID
        for episode in episodes {
            if let existing = try await downloadRepository.fetch(
                itemId: episode.itemId, serverId: serverId)
            {
                logger.info(
                    "Episode \(episode.itemId.rawValue) already exists: state=\(existing.state.rawValue)"
                )
                continue
            }

            let item = DownloadItem(
                id: UUID().uuidString,
                itemId: episode.itemId,
                serverId: serverId,
                title: episode.title,
                mediaType: .episode,
                state: .queued,
                progress: 0,
                totalBytes: 0,
                downloadedBytes: 0,
                localFilePath: nil,
                remoteURL: episode.remoteURL.absoluteString,
                parentId: seriesItemId,
                groupId: group.id,
                artworkURL: nil,
                errorMessage: nil,
                createdAt: Date(),
                completedAt: nil
            )
            try await downloadRepository.save(item)
        }

        logger.info("Enqueued \(episodes.count) episodes for '\(groupTitle)' [group: \(group.id)]")
        await startNextDownloadsIfNeeded()
        return group
    }

    // MARK: - Public API — Group Queries

    /// Check if all downloads in a group are completed.
    public func isGroupComplete(groupId: String) async -> Bool {
        guard let items = try? await downloadRepository.fetchAll() else { return false }
        let groupItems = items.filter { $0.groupId == groupId }
        guard !groupItems.isEmpty else { return false }
        return groupItems.allSatisfy { $0.state == .completed }
    }

    /// Delete all downloads in a group, plus the group record itself.
    public func deleteGroup(id: String) async throws {
        // Get all items in the group
        let allItems = try await downloadRepository.fetchAll()
        let groupItems = allItems.filter { $0.groupId == id }

        // Delete each item (cancels tasks, removes files)
        for item in groupItems {
            try await deleteDownload(id: item.id)
        }

        // Delete the group record
        try await groupRepository?.delete(id: id)
        logger.info("Deleted download group \(id) with \(groupItems.count) items")
    }

    // MARK: - Public API — Pause / Resume / Cancel / Retry

    /// Pause an active download, preserving resume data if possible.
    public func pauseDownload(id: String) async throws {
        guard let item = try await downloadRepository.fetch(id: id) else { return }
        guard item.state == .downloading else {
            logger.warning("Cannot pause download \(id) in state \(item.state.rawValue)")
            return
        }

        // Find the task and cancel with resume data
        let taskIdentifier = state.withLock {
            $0.taskToDownloadID.first(where: { $0.value == id })?.key
        }
        if let taskId = taskIdentifier {
            let tasks = await urlSession.allTasks
            if let task = tasks.first(where: { $0.taskIdentifier == taskId })
                as? URLSessionDownloadTask
            {
                // Use a continuation to bridge the callback-based API
                let resumeData: Data? = await withCheckedContinuation { continuation in
                    task.cancel(byProducingResumeData: { data in
                        continuation.resume(returning: data)
                    })
                }
                if let data = resumeData {
                    state.withLock { $0.resumeDataCache[id] = data }
                    logger.debug("Stored resume data for \(id) (\(data.count) bytes)")
                }
            }
            state.withLock { state in
                state.taskToDownloadID.removeValue(forKey: taskId)
                state.activeDownloadCount = max(0, state.activeDownloadCount - 1)
            }
        }

        try await downloadRepository.updateState(id: id, state: .paused, errorMessage: nil)
        logger.info("Paused download: \(id)")

        await startNextDownloadsIfNeeded()
    }

    /// Resume a paused or queued download.
    public func resumeDownload(id: String) async throws {
        guard let item = try await downloadRepository.fetch(id: id) else { return }
        guard item.state == .paused || item.state == .queued else {
            logger.warning("Cannot resume download \(id) in state \(item.state.rawValue)")
            return
        }

        // Move back to queued so the scheduler will pick it up.
        try await downloadRepository.updateState(id: id, state: .queued, errorMessage: nil)
        logger.info("Re-queued download for resume: \(id)")

        await startNextDownloadsIfNeeded()
    }

    /// Cancel and remove an active or queued download (does NOT delete the database record;
    /// use ``deleteDownload(id:)`` for a full removal).
    public func cancelDownload(id: String) async throws {
        // Cancel the URLSession task if active
        let taskId = state.withLock { $0.taskToDownloadID.first(where: { $0.value == id })?.key }
        if let taskId {
            let tasks = await urlSession.allTasks
            tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
            state.withLock { state in
                state.taskToDownloadID.removeValue(forKey: taskId)
                state.activeDownloadCount = max(0, state.activeDownloadCount - 1)
            }
        }

        state.withLock { _ = $0.resumeDataCache.removeValue(forKey: id) }

        try await downloadRepository.updateState(id: id, state: .failed, errorMessage: "Cancelled")
        logger.info("Cancelled download: \(id)")

        await startNextDownloadsIfNeeded()
    }

    /// Retry a failed download from the beginning (or with resume data if available).
    public func retryDownload(id: String) async throws {
        guard let item = try await downloadRepository.fetch(id: id) else { return }
        guard item.state == .failed else {
            logger.warning("Cannot retry download \(id) in state \(item.state.rawValue)")
            return
        }

        try await downloadRepository.updateState(id: id, state: .queued, errorMessage: nil)
        try await downloadRepository.updateProgress(id: id, downloadedBytes: 0, progress: 0)
        logger.info("Retrying download: \(id)")

        await startNextDownloadsIfNeeded()
    }

    // MARK: - Public API — Queries

    /// All downloads across every server, ordered by creation date (newest first).
    public func allDownloads() async throws -> [DownloadItem] {
        try await downloadRepository.fetchAll()
    }

    /// All downloads for a particular server, ordered by creation date (newest first).
    public func downloads(for serverId: String) async throws -> [DownloadItem] {
        try await downloadRepository.fetchAll(serverId: serverId)
    }

    /// Look up a download by the media item's Jellyfin ID and server.
    public func download(for itemId: ItemID, serverId: String) async throws -> DownloadItem? {
        try await downloadRepository.fetch(itemId: itemId, serverId: serverId)
    }

    // MARK: - Public API — Deletion

    /// Delete a single download: cancel any in-progress transfer, remove the
    /// on-disk file, and delete the database record.
    public func deleteDownload(id: String) async throws {
        // Cancel any active task
        let taskId = state.withLock { $0.taskToDownloadID.first(where: { $0.value == id })?.key }
        if let taskId {
            let tasks = await urlSession.allTasks
            tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
            state.withLock { state in
                state.taskToDownloadID.removeValue(forKey: taskId)
                state.activeDownloadCount = max(0, state.activeDownloadCount - 1)
            }
        }

        state.withLock { _ = $0.resumeDataCache.removeValue(forKey: id) }

        // Delete files
        if let item = try await downloadRepository.fetch(id: id) {
            try? storage.deleteFiles(for: item)
        }

        // Delete DB record
        try await downloadRepository.delete(id: id)
        logger.info("Deleted download: \(id)")

        await startNextDownloadsIfNeeded()
    }

    /// Delete all downloads for a server.
    public func deleteAllDownloads(serverId: String) async throws {
        // Cancel active tasks belonging to this server
        let items = try await downloadRepository.fetchAll(serverId: serverId)
        let itemIDs = Set(items.map(\.id))

        let tasks = await urlSession.allTasks
        state.withLock { state in
            for (taskId, downloadId) in state.taskToDownloadID where itemIDs.contains(downloadId) {
                tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
                state.taskToDownloadID.removeValue(forKey: taskId)
            }
            for itemId in itemIDs {
                state.resumeDataCache.removeValue(forKey: itemId)
            }
            state.activeDownloadCount = max(0, state.activeDownloadCount - itemIDs.count)
        }

        // Delete all files for this server
        try? storage.deleteAllFiles(serverId: serverId)

        // Delete all DB records
        try await downloadRepository.deleteAll(serverId: serverId)
        logger.info("Deleted all downloads for server \(serverId)")

        await startNextDownloadsIfNeeded()
    }

    // MARK: - Public API — Storage

    /// Total bytes of completed downloads for a specific server (from the DB).
    public func totalStorageUsed(serverId: String) async throws -> Int64 {
        try await downloadRepository.totalDownloadedBytes(serverId: serverId)
    }

    /// Resolve a `DownloadItem`'s local file path to an absolute `URL`.
    ///
    /// Returns `nil` if the item has no `localFilePath` or the file does not
    /// exist on disk.
    public func localFileURL(for downloadItem: DownloadItem) -> URL? {
        guard let relativePath = downloadItem.localFilePath else { return nil }
        let url = storage.resolveAbsoluteURL(relativePath: relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Public API — App Lifecycle

    /// Reconcile database state with the URLSession task list after an app restart.
    ///
    /// Call this once during app launch. It:
    /// 1. Re-maps any still-running background tasks to their download IDs.
    /// 2. Moves any orphaned `.downloading` records back to `.queued`.
    /// 3. Kicks the scheduler to start new downloads.
    public func restoreDownloadsOnLaunch() async {
        logger.info("Restoring downloads on launch…")

        // 1. Get all tasks the background session still knows about.
        let existingTasks = await urlSession.allTasks
        var runningTaskDescriptions: [Int: String] = [:]  // taskIdentifier → original URL string
        for task in existingTasks {
            if let url = task.originalRequest?.url?.absoluteString {
                runningTaskDescriptions[task.taskIdentifier] = url
            }
        }
        // Freeze as a let so it can be captured by the @Sendable withLock closure.
        let taskDescriptions = runningTaskDescriptions

        // 2. Fetch DB items that think they are downloading or queued.
        let downloading = (try? await downloadRepository.fetchAll(state: .downloading)) ?? []
        let queued = (try? await downloadRepository.fetchAll(state: .queued)) ?? []
        let inFlight = downloading + queued

        // 3. For each in-flight item, check if the session still has a matching task.
        //    The withLock closure returns the list of orphaned download IDs that need
        //    re-queuing, computed entirely inside the lock.
        let orphanedIDs: [String] = state.withLock { state in
            var usedTaskIds = Set<Int>()
            var orphaned: [String] = []

            for item in inFlight {
                var matched = false
                for (taskId, taskURL) in taskDescriptions where !usedTaskIds.contains(taskId) {
                    if taskURL == item.remoteURL {
                        state.taskToDownloadID[taskId] = item.id
                        matched = true
                        usedTaskIds.insert(taskId)
                        break
                    }
                }

                if !matched && item.state == .downloading {
                    orphaned.append(item.id)
                }
            }
            state.activeDownloadCount = state.taskToDownloadID.count
            return orphaned
        }

        // Update orphaned items outside the lock
        for orphanID in orphanedIDs {
            try? await downloadRepository.updateState(
                id: orphanID, state: .queued, errorMessage: nil)
        }

        let reconciledCount = inFlight.count - orphanedIDs.count
        logger.info(
            "Restored \(reconciledCount) active task(s); \(orphanedIDs.count) re-queued"
        )

        // 4. Kick the scheduler.
        await startNextDownloadsIfNeeded()
    }

    // MARK: - Internal — Scheduling

    /// Look at the queue and start tasks until the concurrency limit is reached.
    internal func startNextDownloadsIfNeeded() async {
        while true {
            // WiFi-only gate: don't start new downloads on cellular if restricted
            if isWifiOnlyEnabled() && NetworkMonitor.shared.isExpensive {
                logger.info("WiFi-only mode enabled and on cellular — pausing download queue")
                break
            }

            let slotsAvailable = state.withLock {
                Self.maxConcurrentDownloads - $0.activeDownloadCount
            }

            guard slotsAvailable > 0 else { break }

            // Fetch the next queued item (oldest first).
            guard let queuedItems = try? await downloadRepository.fetchAll(state: .queued),
                let next = queuedItems.first
            else {
                break
            }

            await startDownloadTask(for: next)
        }
    }

    /// Create (or resume) a `URLSessionDownloadTask` for a single item.
    private func startDownloadTask(for item: DownloadItem) async {
        guard let url = URL(string: item.remoteURL) else {
            logger.error("Invalid remote URL for download \(item.id): \(item.remoteURL)")
            try? await downloadRepository.updateState(
                id: item.id, state: .failed, errorMessage: "Invalid download URL")
            return
        }

        // Prepare the destination directory
        do {
            try storage.prepareDirectory(for: item)
        } catch {
            logger.error(
                "Failed to prepare directory for \(item.id): \(error.localizedDescription)")
            try? await downloadRepository.updateState(
                id: item.id, state: .failed,
                errorMessage: "Could not prepare storage: \(error.localizedDescription)")
            return
        }

        // Check for resume data
        let resumeData = state.withLock { $0.resumeDataCache.removeValue(forKey: item.id) }

        let task: URLSessionDownloadTask
        if let resumeData {
            task = urlSession.downloadTask(withResumeData: resumeData)
            logger.debug(
                "Resuming download \(item.id) with \(resumeData.count) bytes of resume data")
        } else {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            task = urlSession.downloadTask(with: request)
        }

        task.taskDescription = item.id  // belt-and-suspenders: store ID on the task too

        // Register mapping
        state.withLock { state in
            state.taskToDownloadID[task.taskIdentifier] = item.id
            state.activeDownloadCount += 1
        }

        // Update DB state
        try? await downloadRepository.updateState(
            id: item.id, state: .downloading, errorMessage: nil)

        task.resume()
        logger.info("Started download task \(task.taskIdentifier) for \(item.title) [\(item.id)]")
    }

    // MARK: - Internal — Delegate Callbacks

    /// Called by the delegate when periodic progress is reported.
    internal func handleProgress(
        taskIdentifier: Int,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let downloadID = state.withLock({ $0.taskToDownloadID[taskIdentifier] }) else {
            return
        }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0
        }

        Task { [downloadRepository] in
            try? await downloadRepository.updateProgress(
                id: downloadID,
                downloadedBytes: totalBytesWritten,
                progress: min(progress, 1.0)
            )
        }
    }

    /// Called by the delegate when the file has been downloaded to a temporary location.
    internal func handleDownloadFinished(
        taskIdentifier: Int, location: URL
    ) {
        guard let downloadID = state.withLock({ $0.taskToDownloadID[taskIdentifier] }) else {
            logger.warning(
                "Received download completion for unknown task \(taskIdentifier)")
            return
        }

        // IMPORTANT: The temporary file at `location` is deleted by the system
        // as soon as this delegate callback returns. We MUST move it to a
        // location we control *synchronously*, before returning.
        let fm = FileManager.default
        let stagingDir = storage.downloadsDirectory.appendingPathComponent(
            ".staging", isDirectory: true)
        let stagedFile = stagingDir.appendingPathComponent(downloadID)

        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: stagedFile.path) {
                try fm.removeItem(at: stagedFile)
            }
            try fm.moveItem(at: location, to: stagedFile)
        } catch {
            logger.error(
                "Failed to stage downloaded file for \(downloadID): \(error.localizedDescription)")
            Task { [downloadRepository] in
                try? await downloadRepository.updateState(
                    id: downloadID, state: .failed,
                    errorMessage: "File staging failed: \(error.localizedDescription)")
            }
            return
        }

        // Now that the file is safely staged, perform the async DB lookup
        // and final move to permanent storage.
        Task { [downloadRepository, storage, logger] in
            guard let item = try? await downloadRepository.fetch(id: downloadID) else {
                logger.error("No DB record for completed download \(downloadID)")
                try? fm.removeItem(at: stagedFile)
                return
            }

            do {
                let relativePath = try storage.moveToPermamentStorage(
                    from: stagedFile, for: item)
                try await downloadRepository.markCompleted(
                    id: downloadID, localFilePath: relativePath)
                logger.info("Download completed: \(item.title) → \(relativePath)")
            } catch {
                logger.error(
                    "Failed to move/complete download \(downloadID): \(error.localizedDescription)"
                )
                try? await downloadRepository.updateState(
                    id: downloadID, state: .failed,
                    errorMessage: "File move failed: \(error.localizedDescription)")
            }
        }
    }

    /// Called by the delegate when a task completes (possibly with an error).
    internal func handleTaskCompleted(
        taskIdentifier: Int, error: (any Error)?
    ) {
        let downloadID: String? = state.withLock { state in
            guard let id = state.taskToDownloadID[taskIdentifier] else { return nil }
            state.taskToDownloadID.removeValue(forKey: taskIdentifier)
            state.activeDownloadCount = max(0, state.activeDownloadCount - 1)
            return id
        }

        guard let downloadID else { return }

        if let error {
            let nsError = error as NSError

            // Check for resume data in the error userInfo (e.g. connectivity loss).
            if let resumeData = nsError.userInfo[Self.resumeDataKey] as? Data {
                state.withLock { $0.resumeDataCache[downloadID] = resumeData }
                logger.debug(
                    "Stored \(resumeData.count) bytes of resume data for \(downloadID) from error"
                )
            }

            // URLError.cancelled is expected when we intentionally pause/cancel.
            if nsError.code == NSURLErrorCancelled {
                logger.debug("Task \(taskIdentifier) cancelled for download \(downloadID)")
            } else {
                logger.error(
                    "Download \(downloadID) failed: \(error.localizedDescription)")
                Task { [downloadRepository] in
                    try? await downloadRepository.updateState(
                        id: downloadID, state: .failed,
                        errorMessage: error.localizedDescription)
                }
            }
        }

        // Whether or not there was an error, try to start the next queued download.
        Task {
            await startNextDownloadsIfNeeded()
        }

        // Check for group completion
        Task { [weak self] in
            guard let self else { return }
            // Only check if the task completed without error (meaning it finished downloading)
            if error == nil {
                await self.checkGroupCompletion(downloadId: downloadID)
            }
        }
    }

    /// After a download completes, check if its group is now fully complete.
    private func checkGroupCompletion(downloadId: String) async {
        guard let item = try? await downloadRepository.fetch(id: downloadId),
            let groupId = item.groupId,
            await isGroupComplete(groupId: groupId),
            let group = try? await groupRepository?.fetch(id: groupId)
        else { return }

        logger.info("Download group '\(group.title)' [\(group.id)] is now complete")

        // Post a local notification
        await postGroupCompletionNotification(group: group)
    }

    /// Post a local notification that a download group has finished.
    private func postGroupCompletionNotification(group: DownloadGroup) async {
        let content = UNMutableNotificationContent()

        switch group.mediaType {
        case .album:
            content.title = "Download Complete"
            content.body = "\(group.title) is ready to listen."
        case .season, .series:
            content.title = "Download Complete"
            content.body = "\(group.title) is ready to watch."
        default:
            content.title = "Download Complete"
            content.body = "\(group.title) is ready."
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "group-complete-\(group.id)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        try? await UNUserNotificationCenter.current().add(request)
        logger.info("Posted completion notification for group '\(group.title)'")
    }

    /// Called by the delegate when the background session is reconstituted
    /// by the system and all enqueued messages have been delivered.
    internal func handleSessionDidFinishEvents() {
        logger.info("Background session finished delivering events")
    }
}

// MARK: - SessionDelegate

/// A helper class that bridges `URLSessionDownloadDelegate` callbacks to
/// `DownloadManagerService`.
///
/// The delegate must be a separate `NSObject` subclass because `URLSession`
/// retains its delegate strongly, and we need a reference cycle-safe design.
/// The `service` back-pointer is set immediately after init by the owning
/// `DownloadManagerService`.
private final class SessionDelegate: NSObject,
    URLSessionDownloadDelegate,
    @unchecked Sendable
{

    /// Back-pointer to the owning service. Set immediately after init.
    var service: DownloadManagerService!

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        service.handleDownloadFinished(
            taskIdentifier: downloadTask.taskIdentifier, location: location)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        service.handleProgress(
            taskIdentifier: downloadTask.taskIdentifier,
            bytesWritten: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        // Update progress to reflect the resumed offset so the UI doesn't
        // jump backwards to 0.
        service.handleProgress(
            taskIdentifier: downloadTask.taskIdentifier,
            bytesWritten: 0,
            totalBytesWritten: fileOffset,
            totalBytesExpectedToWrite: expectedTotalBytes
        )
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        service.handleTaskCompleted(
            taskIdentifier: task.taskIdentifier, error: error)
    }

    // MARK: URLSessionDelegate

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        service.handleSessionDidFinishEvents()
    }
}
