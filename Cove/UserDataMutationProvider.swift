import Foundation
import JellyfinProvider
import Models

// MARK: - Mutation Provider Protocol

/// Abstracts the server-side user data mutation calls.
///
/// Extracted from the concrete provider to enable testing `UserDataStore`
/// with a mock implementation.
protocol UserDataMutationProvider: Sendable {
    func setFavorite(itemId: ItemID, isFavorite: Bool) async throws
    func setPlayed(itemId: ItemID, isPlayed: Bool) async throws
}

/// `JellyfinServerProvider` already implements both methods — this conformance
/// is automatic (no additional code needed).
extension JellyfinServerProvider: UserDataMutationProvider {}
