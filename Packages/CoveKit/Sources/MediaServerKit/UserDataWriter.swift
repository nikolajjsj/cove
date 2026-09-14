import Foundation
import Models

/// What the outbox flusher needs from a server: one idempotent call per change,
/// plus a read of the current position for the one field that merges instead
/// of overwriting.
public protocol UserDataWriter: Sendable {
    func writePlayed(itemId: String, isPlayed: Bool, at date: Date) async throws
    func writeFavorite(itemId: String, isFavorite: Bool) async throws
    func writePosition(itemId: String, ticks: Int64, played: Bool, at date: Date) async throws
    /// The server's current position and played flag, for the merge rule:
    /// the greater position wins unless the item was marked played.
    func currentPosition(itemId: String) async throws -> (ticks: Int64, played: Bool)
}
