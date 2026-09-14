import Foundation
import MediaServerKit
import Models
import Persistence
import os

/// Fills the local catalogue from a server and keeps it honest.
///
/// One actor per signed-in `(server, user)`. It owns the three passes — bootstrap,
/// delta, reconcile — and serialises them: reconcile racing bootstrap would sweep
/// rows bootstrap has not reached yet. Every page is its own transaction and a
/// cursor advances only after the *last* page of a pass commits, so cancellation
/// at any point leaves the database consistent and the next run resumes.
///
/// Pure logic lives in `Reconciliation` and `CursorPolicy`; this actor is the loop.
public actor CatalogSyncEngine {
    public struct Library: Hashable, Sendable {
        public let id: String
        public let name: String
        /// Server type strings this library contributes to the catalogue.
        public let itemTypes: [String]

        public init(id: String, name: String, itemTypes: [String]) {
            self.id = id
            self.name = name
            self.itemTypes = itemTypes
        }
    }

    private let source: any CatalogSyncSource
    private let repository: CatalogRepository
    private let scope: CatalogRepository.Scope
    private let pageSize: Int
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Sync")

    private var isRunning = false
    private var statusContinuations: [UUID: AsyncStream<CatalogSyncStatus>.Continuation] = [:]
    public private(set) var status: CatalogSyncStatus = .idle

    public init(
        source: any CatalogSyncSource,
        repository: CatalogRepository,
        scope: CatalogRepository.Scope,
        pageSize: Int = 200
    ) {
        self.source = source
        self.repository = repository
        self.scope = scope
        self.pageSize = pageSize
    }

    // MARK: - Status

    public var statusStream: AsyncStream<CatalogSyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            statusContinuations[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }

    private func publish(_ new: CatalogSyncStatus) {
        status = new
        for c in statusContinuations.values { c.yield(new) }
    }

    // MARK: - Entry points

    /// What the app calls on foreground and after sign-in: bootstrap anything that
    /// has not finished, delta everything that has.
    public func syncIfNeeded(libraries: [Library]) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            for library in libraries {
                let state = try await repository.syncState(scope: scope, key: Self.bootstrapKey(library.id))
                if state.bootstrapComplete {
                    try await delta(library)
                } else {
                    try await bootstrap(library)
                }
            }
            publish(.idle)
        } catch {
            handle(error)
        }
    }

    /// Full bidirectional reconcile of every library. Daily, and on pull-to-refresh.
    public func reconcileAll(libraries: [Library]) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            publish(.syncing)
            for library in libraries {
                try await reconcile(library)
            }
            publish(.idle)
        } catch {
            handle(error)
        }
    }

    /// Libraries that vanished from the server, after `/UserViews` succeeded.
    /// An empty list on a 5xx is not "no libraries" — the caller only passes a
    /// list it actually received.
    public func removeLibraries(notIn current: [Library], known: [String]) async {
        let currentIds = Set(current.map(\.id))
        for id in known where !currentIds.contains(id) {
            do {
                try await repository.deleteLibrary(libraryId: id, scope: scope)
                logger.info("Removed vanished library \(id)")
            } catch {
                logger.error("Failed removing library \(id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bootstrap

    /// Pages the whole library oldest-first, committing each page with its next
    /// index, then sets the delta cursor to the *first* page's server time and runs
    /// one reconcile to backfill whatever the offset walk skipped.
    func bootstrap(_ library: Library) async throws {
        let key = Self.bootstrapKey(library.id)
        var state = try await repository.syncState(scope: scope, key: key)
        var index = state.bootstrapNextIndex
        var firstServerDate: Date? = state.cursor  // survives a resumed bootstrap
        var total = 0

        logger.info("Bootstrap \(library.name) from index \(index)")
        publish(.bootstrapping(libraryName: library.name, done: index, total: 0))

        repeat {
            try Task.checkCancellation()
            let page = try await source.catalogPage(
                libraryId: library.id, itemTypes: library.itemTypes, startIndex: index, limit: pageSize)
            total = page.totalCount
            if firstServerDate == nil {
                firstServerDate = page.serverDate
                // Persist immediately so a resume after a kill keeps the *earliest*
                // clock reading, which is the only safe cursor for a walk that
                // spans time.
                state.cursor = firstServerDate
                try await repository.saveSyncState(state)
            }
            let entries = page.entries.map { e in var c = e; c.libraryId = library.id; return c }
            index += page.entries.count
            try await repository.upsertBootstrapPage(entries, nextIndex: index, scope: scope, key: key)
            publish(.bootstrapping(libraryName: library.name, done: min(index, total), total: total))
            if page.entries.isEmpty { break }
        } while index < total

        state = try await repository.syncState(scope: scope, key: key)
        state.bootstrapComplete = true
        state.cursor = firstServerDate
        state.lastRunAt = Date()
        state.lastError = nil
        try await repository.saveSyncState(state)
        logger.info("Bootstrap \(library.name) complete: \(index) items")

        try await reconcile(library)
    }

    // MARK: - Delta

    /// Additions and edits since the cursor. The cursor is server time from the
    /// first page's `Date` header and moves only after the last page commits.
    func delta(_ library: Library) async throws {
        let key = Self.bootstrapKey(library.id)
        var state = try await repository.syncState(scope: scope, key: key)
        guard let cursor = state.cursor else {
            // No cursor means bootstrap never recorded one; treat as not bootstrapped.
            state.bootstrapComplete = false
            try await repository.saveSyncState(state)
            return try await bootstrap(library)
        }

        publish(.syncing)
        let since = CursorPolicy.since(cursor: cursor)
        var index = 0
        var candidate: Date?
        var total = 0

        repeat {
            try Task.checkCancellation()
            let page = try await source.catalogChanges(
                libraryId: library.id, itemTypes: library.itemTypes, since: since,
                startIndex: index, limit: pageSize)
            if candidate == nil { candidate = page.serverDate }
            total = page.totalCount
            if total > CursorPolicy.rebootstrapThreshold {
                logger.warning("Delta for \(library.name) is \(total) rows; re-bootstrapping")
                try await repository.deleteLibrary(libraryId: library.id, scope: scope)
                state.bootstrapComplete = false
                state.bootstrapNextIndex = 0
                state.cursor = nil
                try await repository.saveSyncState(state)
                return try await bootstrap(library)
            }
            let entries = page.entries.map { e in var c = e; c.libraryId = library.id; return c }
            try await repository.upsert(entries, scope: scope)
            index += page.entries.count
            if page.entries.isEmpty { break }
        } while index < total

        // Only now. A pass that failed on page 7 of 9 never reaches this line and
        // re-runs from the old cursor; upserts make the repeat harmless.
        state.cursor = candidate ?? state.cursor
        state.lastRunAt = Date()
        state.lastError = nil
        try await repository.saveSyncState(state)
        if total > 0 { logger.info("Delta \(library.name): \(total) changed") }
    }

    // MARK: - Reconcile

    /// Bidirectional. Removes what the server no longer lists, fetches what the
    /// server lists that the catalogue lacks, and stamps everything it saw.
    func reconcile(_ library: Library) async throws {
        var serverIds = Set<String>()
        var index = 0
        var total = 0
        var seenAt: Date?
        repeat {
            try Task.checkCancellation()
            let page = try await source.catalogIds(
                libraryId: library.id, itemTypes: library.itemTypes, startIndex: index, limit: 500)
            if seenAt == nil { seenAt = page.serverDate }
            total = page.totalCount
            serverIds.formUnion(page.ids)
            index += page.ids.count
            if page.ids.isEmpty { break }
        } while index < total

        let localIds = try await repository.itemIds(libraryId: library.id, scope: scope)
        let outcome = Reconciliation.diff(server: serverIds, local: localIds)

        if !outcome.missing.isEmpty {
            let entries = try await source.catalogEntries(ids: outcome.missing, libraryId: library.id)
            try await repository.upsert(entries, scope: scope)
            logger.info("Reconcile \(library.name): backfilled \(entries.count)")
        }
        if !outcome.phantoms.isEmpty {
            try await repository.delete(itemIds: outcome.phantoms, scope: scope)
            logger.info("Reconcile \(library.name): removed \(outcome.phantoms.count) phantoms")
        }
        try await repository.markSeen(itemIds: Array(serverIds), at: seenAt ?? Date(), scope: scope)

        var state = try await repository.syncState(scope: scope, key: Self.reconcileKey(library.id))
        state.lastRunAt = Date()
        state.lastError = nil
        try await repository.saveSyncState(state)
    }

    // MARK: - Errors

    private func handle(_ error: any Error) {
        let kind = SyncErrorClass.classify(error)
        switch kind {
        case .transient:
            logger.warning("Sync paused: \(error.localizedDescription)")
            publish(.failed(error.localizedDescription))
        case .auth:
            logger.warning("Sync stopped: sign in again")
            publish(.failed("Sign in again to keep your library up to date."))
        case .permanentItem:
            logger.info("Sync skipped an item: \(error.localizedDescription)")
            publish(.idle)
        case .permanentPass:
            logger.error("Sync bug: \(error.localizedDescription)")
            publish(.failed(error.localizedDescription))
        }
    }

    // MARK: - Keys

    static func bootstrapKey(_ libraryId: String) -> String { "catalog:\(libraryId)" }
    static func reconcileKey(_ libraryId: String) -> String { "reconcile:\(libraryId)" }

    /// The server type strings a library contributes. Music is excluded upstream by
    /// the caller (FeatureFlags); this is about shape, not policy.
    public static func itemTypes(for collectionType: CollectionType?) -> [String]? {
        switch collectionType {
        case .movies: return ["Movie"]
        case .tvshows: return ["Series", "Season", "Episode"]
        case .boxsets: return ["BoxSet"]
        default: return nil
        }
    }
}
