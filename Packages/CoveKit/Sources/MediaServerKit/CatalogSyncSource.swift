import Foundation
import Models

/// What the catalogue sync engine needs from a server, and nothing more.
///
/// Every method is per library and every page carries the server's clock. A
/// backend implements this once and the engine, the repository and every view
/// stay untouched — which is the whole point of the local-first design.
public protocol CatalogSyncSource: Sendable {
    /// One page of the full catalogue for a library, oldest `DateCreated` first so
    /// additions land past the cursor rather than shifting the unread tail.
    func catalogPage(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> CatalogPage

    /// Items whose metadata the server saved at or after `since`. Additions and
    /// edits only — deletions are never reported and are reconcile's job.
    func catalogChanges(
        libraryId: String, itemTypes: [String], since: Date, startIndex: Int, limit: Int
    ) async throws -> CatalogPage

    /// Bare ids for a library, the cheapest projection the server offers.
    func catalogIds(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> CatalogIdPage

    /// Full catalogue-tier entries for specific ids — reconcile's backfill.
    func catalogEntries(ids: [String], libraryId: String) async throws -> [CatalogEntry]

    // MARK: User-data sweeps
    //
    // There is no user-data delta on Jellyfin 12 — `minDateLastSavedForUser` does not
    // track user-data writes — so user data is pulled as the sets the server already
    // indexes. Each of these was verified to reflect a write immediately.

    /// Everything in progress for this user, with positions.
    func resumeUserData() async throws -> [CatalogUserDataRow]
    /// Ids of every favourite.
    func favoriteIds() async throws -> Set<String>
    /// The most recently played items, newest first.
    func recentlyPlayedUserData(limit: Int) async throws -> [CatalogUserDataRow]
    /// One page of user data for a whole library — the daily full sweep.
    func userDataPage(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> (rows: [CatalogUserDataRow], totalCount: Int)
}
