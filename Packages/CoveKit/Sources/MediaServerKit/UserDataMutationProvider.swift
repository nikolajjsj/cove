import Foundation
import Models

/// Abstracts server-side user data mutation calls (favorite, played/watched state).
///
/// Extracted into its own protocol to enable testing ``UserDataStore`` with a mock
/// implementation. Any server provider that supports user data mutations should
/// conform to this protocol.
public protocol UserDataMutationProvider: Sendable {
    /// Set the favorite state for an item.
    func setFavorite(itemId: ItemID, isFavorite: Bool) async throws
    /// Set the played/watched state for an item.
    func setPlayed(itemId: ItemID, isPlayed: Bool) async throws
}
