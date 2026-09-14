import Foundation
import GRDB
import Models
import os

/// Pending user-data writes, and the rule that makes them safe.
///
/// A tap always succeeds locally: `enqueue` applies the change to
/// `catalog_user_data` and records the outbox row in the same transaction. While
/// the row is pending, `CatalogRepository` refuses to overwrite that field from
/// any server response — the pending write is the truth until acknowledged.
///
/// At most one row per (item, field): a later write for the same pair replaces
/// the earlier one, so six offline toggles reach the server as one request.
public final class UserDataOutboxRepository: Sendable {
    private let database: DatabaseManager
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Outbox")

    public init(database: DatabaseManager) {
        self.database = database
    }

    public typealias Scope = CatalogRepository.Scope

    /// Apply locally and queue for the server, atomically.
    public func enqueue(_ change: UserDataChange, itemId: String, scope: Scope) async throws {
        try await database.dbWriter.write { db in
            // 1. Local truth. Create the user-data row if the catalogue has the item
            //    but no user data yet; skip silently if the item is unknown — a
            //    catalogue that has never seen the item cannot show it anyway.
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM catalog_items WHERE serverId = ? AND userId = ? AND itemId = ?)",
                arguments: [scope.serverId, scope.userId, itemId]) ?? false
            if exists {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO catalog_user_data (serverId, userId, itemId, played, playCount, isFavorite, playbackPositionTicks)
                        VALUES (?, ?, ?, 0, 0, 0, 0)
                        """,
                    arguments: [scope.serverId, scope.userId, itemId])
                switch change {
                case .played(let v, let at):
                    try db.execute(
                        sql: "UPDATE catalog_user_data SET played = ?, playCount = CASE WHEN ? THEN playCount + 1 ELSE playCount END, lastPlayedDate = CASE WHEN ? THEN ? ELSE lastPlayedDate END, playbackPositionTicks = CASE WHEN ? THEN 0 ELSE playbackPositionTicks END WHERE serverId = ? AND userId = ? AND itemId = ?",
                        arguments: [v, v, v, at, v, scope.serverId, scope.userId, itemId])
                case .favorite(let v, _):
                    try db.execute(
                        sql: "UPDATE catalog_user_data SET isFavorite = ? WHERE serverId = ? AND userId = ? AND itemId = ?",
                        arguments: [v, scope.serverId, scope.userId, itemId])
                case .position(let ticks, let played, let at):
                    try db.execute(
                        sql: "UPDATE catalog_user_data SET playbackPositionTicks = ?, lastPlayedDate = ?, played = CASE WHEN ? THEN 1 ELSE played END, playCount = CASE WHEN ? AND played = 0 THEN playCount + 1 ELSE playCount END WHERE serverId = ? AND userId = ? AND itemId = ?",
                        arguments: [played ? 0 : ticks, at, played, played, scope.serverId, scope.userId, itemId])
                }
            }

            // 2. The outbox row, replacing any pending write for the same field.
            try db.execute(
                sql: """
                    INSERT INTO user_data_outbox (id, serverId, userId, itemId, field, value, occurredAt, attempts)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(serverId, userId, itemId, field) DO UPDATE SET
                        id = excluded.id, value = excluded.value, occurredAt = excluded.occurredAt,
                        attempts = 0, lastAttemptAt = NULL, lastError = NULL
                    """,
                arguments: [UUID().uuidString, scope.serverId, scope.userId, itemId, change.field, change.encodedValue, change.occurredAt])
        }
    }

    /// Everything waiting, oldest first, so replay lands in the order it happened.
    public func pending(scope: Scope) async throws -> [PendingUserDataChange] {
        try await database.dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, itemId, field, value, attempts FROM user_data_outbox WHERE serverId = ? AND userId = ? ORDER BY occurredAt, rowid",
                arguments: [scope.serverId, scope.userId]
            ).compactMap { row in
                guard let change = UserDataChange(field: row["field"], encodedValue: row["value"]) else { return nil }
                return PendingUserDataChange(id: row["id"], itemId: row["itemId"], change: change, attempts: row["attempts"])
            }
        }
    }

    public func pendingCount(scope: Scope) async throws -> Int {
        try await database.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM user_data_outbox WHERE serverId = ? AND userId = ?",
                             arguments: [scope.serverId, scope.userId]) ?? 0
        }
    }

    /// The server acknowledged it, or it can never succeed. Either way it is gone,
    /// and the field is no longer protected from sweeps.
    public func remove(id: String) async throws {
        try await database.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM user_data_outbox WHERE id = ?", arguments: [id])
        }
    }

    public func recordFailure(id: String, error: String) async throws {
        try await database.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE user_data_outbox SET attempts = attempts + 1, lastAttemptAt = ?, lastError = ? WHERE id = ?",
                arguments: [Date(), error, id])
        }
    }

    public func removeAll(scope: Scope) async throws {
        try await database.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM user_data_outbox WHERE serverId = ? AND userId = ?",
                           arguments: [scope.serverId, scope.userId])
        }
    }
}
