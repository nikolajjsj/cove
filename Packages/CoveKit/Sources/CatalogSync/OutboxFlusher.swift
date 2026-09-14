import Foundation
import MediaServerKit
import Models
import Persistence
import os

/// Replays pending user-data writes to the server, in the order they happened.
///
/// The rules, from the spec (§7):
/// - Replay is ordered by `occurredAt` across items.
/// - Every call is idempotent, so a retried row is harmless.
/// - Failures are classified. A 404 means the item is gone: drop the row and keep
///   going. A 401 stops the pass. Anything transient records an attempt and, after
///   three consecutive failures, stops — but never removes the row.
/// - Position is the one field that merges: the greater position wins unless the
///   item was marked played, because you cannot un-watch by watching less.
///
/// It is the caller's job to flush *before* any user-data sweep, so a sweep can
/// never pull the server's stale value over what the user just did.
public struct OutboxFlusher: Sendable {
    public struct Outcome: Equatable, Sendable {
        public var sent = 0
        public var dropped = 0
        public var yielded = 0
        public var failed = 0
        public var stoppedEarly = false
    }

    private let outbox: UserDataOutboxRepository
    private let writer: any UserDataWriter
    private let scope: CatalogRepository.Scope
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Outbox")

    public init(outbox: UserDataOutboxRepository, writer: any UserDataWriter, scope: CatalogRepository.Scope) {
        self.outbox = outbox
        self.writer = writer
        self.scope = scope
    }

    @discardableResult
    public func flush() async -> Outcome {
        var outcome = Outcome()
        let rows: [PendingUserDataChange]
        do {
            rows = try await outbox.pending(scope: scope)
        } catch {
            logger.error("Could not read outbox: \(error.localizedDescription)")
            return outcome
        }
        guard !rows.isEmpty else { return outcome }

        var consecutiveFailures = 0
        for row in rows {
            if Task.isCancelled { outcome.stoppedEarly = true; break }
            do {
                switch row.change {
                case .played(let value, let at):
                    try await writer.writePlayed(itemId: row.itemId, isPlayed: value, at: at)
                case .favorite(let value, _):
                    try await writer.writeFavorite(itemId: row.itemId, isFavorite: value)
                case .position(let ticks, let played, let at):
                    // Merge, not overwrite. Read first; yield if the server is further
                    // along and this write would not mark it played.
                    let server = try await writer.currentPosition(itemId: row.itemId)
                    if !played && !server.played && server.ticks > ticks {
                        try await outbox.remove(id: row.id)
                        outcome.yielded += 1
                        consecutiveFailures = 0
                        continue
                    }
                    try await writer.writePosition(itemId: row.itemId, ticks: ticks, played: played, at: at)
                }
                try await outbox.remove(id: row.id)
                outcome.sent += 1
                consecutiveFailures = 0
            } catch {
                switch SyncErrorClass.classify(error) {
                case .permanentItem:
                    // The item is gone. Nothing to say to anyone; drop it and go on.
                    try? await outbox.remove(id: row.id)
                    outcome.dropped += 1
                    consecutiveFailures = 0
                case .auth:
                    logger.warning("Outbox stopped: sign in again")
                    outcome.stoppedEarly = true
                    return outcome
                case .permanentPass:
                    // We sent something the server rejects. Retrying will not help;
                    // drop it rather than block everything behind it, and log loudly.
                    logger.error("Outbox row rejected (\(row.change.field)): \(error.localizedDescription)")
                    try? await outbox.remove(id: row.id)
                    outcome.dropped += 1
                case .transient:
                    try? await outbox.recordFailure(id: row.id, error: error.localizedDescription)
                    outcome.failed += 1
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 {
                        logger.warning("Outbox paused after \(consecutiveFailures) consecutive failures")
                        outcome.stoppedEarly = true
                        return outcome
                    }
                }
            }
        }
        if outcome.sent + outcome.dropped + outcome.yielded > 0 {
            logger.info("Outbox: sent \(outcome.sent), yielded \(outcome.yielded), dropped \(outcome.dropped), failed \(outcome.failed)")
        }
        return outcome
    }
}
