import Foundation
import MediaServerKit
import Models
import Persistence

// MARK: - UserDataStore

/// Centralized, observable store for per-item user data (favorite, played, etc.)
/// that applies every edit locally at once and gets it to the server later.
///
/// With an outbox configured, a tap **always succeeds**: the change is written to
/// the local catalogue and queued in the same transaction, the in-memory
/// override updates the UI immediately, and the server hears about it on the
/// next flush — now if online, on reconnect if not. Nothing rolls back. Without an
/// outbox (previews, no database) it falls back to the old call-the-server path.
///
/// Injected into the SwiftUI environment. Views read user data through this
/// store to get the latest optimistic state across all screens. Mutations are
/// applied immediately to the UI, then confirmed (or rolled back) when the
/// server responds.
///
/// ## Reading
/// ```swift
/// let isFav = store.isFavorite(item.id, fallback: item.userData)
/// let data = store.userData(for: item.id, fallback: item.userData)
/// ```
///
/// ## Mutating
/// ```swift
/// try await store.toggleFavorite(itemId: item.id, current: item.userData)
/// try await store.togglePlayed(itemId: item.id, current: item.userData)
/// ```
///
/// ## Reconciliation
/// ```swift
/// store.rebase(item.id, serverData: freshUserData)
/// store.invalidate(item.id)
/// ```
@Observable
@MainActor
final class UserDataStore {

    // MARK: - Types

    enum MutationField: Hashable {
        case favorite
        case played
    }

    // MARK: - State

    /// Per-item UserData overrides. When present, these take priority over
    /// whatever `userData` the `MediaItem` was fetched with.
    private(set) var overrides: [ItemID: UserData] = [:]

    /// Reference counts for in-flight server mutations per field per item.
    /// A field is considered "in-flight" when its count is > 0, preventing
    /// `rebase()` from overwriting the optimistic value.
    private var inflightCounts: [ItemID: [MutationField: Int]] = [:]

    // MARK: - Dependencies

    private let mutationProvider: any UserDataMutationProvider

    /// Set by `CoveApp` once the database is open. Nil means no local catalogue.
    var outbox: UserDataOutboxRepository?
    /// Who the edits belong to. Set by `AppState` when a connection is active.
    var outboxScope: CatalogRepository.Scope?

    private var usesOutbox: Bool { outbox != nil && outboxScope != nil }

    // MARK: - Init

    nonisolated init(provider: any UserDataMutationProvider) {
        self.mutationProvider = provider
    }

    // MARK: - Reading

    /// Returns the effective `UserData` for an item, overlaying any local
    /// overrides on top of the fallback (typically `item.userData`).
    func userData(for itemId: ItemID, fallback: UserData?) -> UserData {
        overrides[itemId] ?? fallback ?? UserData()
    }

    /// Convenience: returns the effective `isFavorite` for an item.
    func isFavorite(_ itemId: ItemID, fallback: UserData?) -> Bool {
        userData(for: itemId, fallback: fallback).isFavorite
    }

    /// Convenience: returns the effective `isPlayed` for an item.
    func isPlayed(_ itemId: ItemID, fallback: UserData?) -> Bool {
        userData(for: itemId, fallback: fallback).isPlayed
    }

    // MARK: - Mutations

    /// Toggle favorite: apply optimistic update → call server → rollback on failure.
    ///
    /// - Returns: The new favorite state after the server confirms.
    /// - Throws: The server error (after rolling back the optimistic update).
    @discardableResult
    func toggleFavorite(itemId: ItemID, current: UserData?) async throws -> Bool {
        let base = userData(for: itemId, fallback: current)
        let originalFavorite = base.isFavorite
        let newValue = !originalFavorite

        // Optimistic update
        var updated = base
        updated.isFavorite = newValue
        overrides[itemId] = updated
        evictOverridesIfNeeded()

        if let outbox, let outboxScope {
            // Local truth + queue, atomically. The flush is somebody else's job.
            try await outbox.enqueue(.favorite(newValue, at: .now), itemId: itemId.rawValue, scope: outboxScope)
            return newValue
        }

        markInflight(itemId, .favorite)
        do {
            try await mutationProvider.setFavorite(itemId: itemId, isFavorite: newValue)
            unmarkInflight(itemId, .favorite)
            return newValue
        } catch {
            // Rollback only the favorite field, preserving other in-flight changes
            unmarkInflight(itemId, .favorite)
            if var current = overrides[itemId] {
                current.isFavorite = originalFavorite
                overrides[itemId] = current
            }
            throw error
        }
    }

    /// Mark an item as played (one-way). No-op if already played.
    ///
    /// Used by the audio player when 95% of a track has been listened to.
    /// Unlike ``togglePlayed(itemId:current:)``, this never un-marks an item.
    ///
    /// - Parameter current: The item's server-side `UserData`. Pass it whenever
    ///   the caller has it: overrides replace the server value wholesale at every
    ///   read site, so basing one on `nil` publishes a blank `UserData` and drops
    ///   the item's favourite state and playback position until it is refetched.
    func markPlayed(itemId: ItemID, current: UserData? = nil) async throws {
        let base = userData(for: itemId, fallback: current)
        guard !base.isPlayed else { return }

        // Optimistic update
        var updated = base
        updated.isPlayed = true
        overrides[itemId] = updated
        evictOverridesIfNeeded()

        if let outbox, let outboxScope {
            try await outbox.enqueue(.played(true, at: .now), itemId: itemId.rawValue, scope: outboxScope)
            return
        }

        markInflight(itemId, .played)
        do {
            try await mutationProvider.setPlayed(itemId: itemId, isPlayed: true)
            unmarkInflight(itemId, .played)
        } catch {
            unmarkInflight(itemId, .played)
            if var rolledBack = overrides[itemId] {
                rolledBack.isPlayed = base.isPlayed
                overrides[itemId] = rolledBack
            }
            throw error
        }
    }

    /// Update local playback state after video playback ends.
    ///
    /// The video player reports progress to the server directly, so this
    /// method only updates the local override for immediate UI reactivity.
    /// Marks the item as played if the user watched at least 90% of the content.
    ///
    /// - Parameters:
    ///   - itemId: The item that was played.
    ///   - position: The final playback position in seconds.
    ///   - runtime: The total runtime of the item in seconds, if known.
    ///   - currentData: The item's existing `UserData` used as a base to
    ///     preserve fields like `isFavorite`.
    func updatePlaybackPosition(
        itemId: ItemID,
        position: TimeInterval,
        runtime: TimeInterval?,
        currentData: UserData?
    ) {
        var data = userData(for: itemId, fallback: currentData)
        data.playbackPosition = position

        // The completion threshold is decided here because offline nobody else
        // can. 90% matches the server's default MaxResumePct.
        let finished = runtime.map { $0 > 0 && position / $0 >= 0.9 } ?? false
        if finished {
            data.isPlayed = true
            data.playCount += 1
            data.lastPlayedDate = .now
            data.playbackPosition = 0
        }

        overrides[itemId] = data
        evictOverridesIfNeeded()

        // Durable: the position lands in the catalogue now and reaches the server
        // on the next flush. Online, the live session report has already said the
        // same thing; the flusher's merge rule makes the repeat harmless.
        if let outbox, let outboxScope {
            let ticks = Int64(position * 10_000_000)
            Task {
                try? await outbox.enqueue(
                    .position(ticks: ticks, played: finished, at: .now),
                    itemId: itemId.rawValue, scope: outboxScope)
            }
        }
    }

    /// Toggle played/watched: apply optimistic update → call server → rollback on failure.
    ///
    /// - Returns: The new played state after the server confirms.
    /// - Throws: The server error (after rolling back the optimistic update).
    @discardableResult
    func togglePlayed(itemId: ItemID, current: UserData?) async throws -> Bool {
        let base = userData(for: itemId, fallback: current)
        let originalPlayed = base.isPlayed
        let newValue = !originalPlayed

        // Optimistic update
        var updated = base
        updated.isPlayed = newValue
        overrides[itemId] = updated
        evictOverridesIfNeeded()

        if let outbox, let outboxScope {
            try await outbox.enqueue(.played(newValue, at: .now), itemId: itemId.rawValue, scope: outboxScope)
            return newValue
        }

        markInflight(itemId, .played)
        do {
            try await mutationProvider.setPlayed(itemId: itemId, isPlayed: newValue)
            unmarkInflight(itemId, .played)
            return newValue
        } catch {
            // Rollback only the played field, preserving other in-flight changes
            unmarkInflight(itemId, .played)
            if var current = overrides[itemId] {
                current.isPlayed = originalPlayed
                overrides[itemId] = current
            }
            throw error
        }
    }

    /// Mark a whole series or season played/unplayed.
    ///
    /// One outbox row for the container — Jellyfin applies it recursively — and
    /// every child episode updated locally so the catalogue agrees at once.
    /// Without an outbox this falls back to the recursive server call.
    func setPlayedRecursively(containerId: ItemID, isPlayed: Bool) async throws {
        invalidate(containerId)
        if let outbox, let outboxScope {
            try await outbox.enqueueRecursivePlayed(
                containerId: containerId.rawValue, isPlayed: isPlayed, at: .now, scope: outboxScope)
            return
        }
        try await mutationProvider.setPlayed(itemId: containerId, isPlayed: isPlayed)
    }

    // MARK: - Reconciliation

    /// Merge fresh server data without clobbering in-flight optimistic updates.
    ///
    /// Call this after re-fetching an item from the server to reconcile the
    /// override with the authoritative server data. Fields with in-flight
    /// mutations are left untouched; all other fields are updated to match.
    func rebase(_ itemId: ItemID, serverData: UserData) {
        guard var existing = overrides[itemId] else { return }

        // Update fields that are NOT currently in-flight
        if !isInflight(itemId, .favorite) {
            existing.isFavorite = serverData.isFavorite
        }
        if !isInflight(itemId, .played) {
            existing.isPlayed = serverData.isPlayed
        }

        // Always update read-only fields from server
        existing.playbackPosition = serverData.playbackPosition
        existing.playCount = serverData.playCount
        existing.lastPlayedDate = serverData.lastPlayedDate

        // If the override now matches the server data and nothing is in-flight, remove it
        if existing == serverData && !hasAnyInflight(itemId) {
            overrides.removeValue(forKey: itemId)
        } else {
            overrides[itemId] = existing
        }
    }

    /// Discard local overrides for an item, but only if no mutations are in-flight.
    func invalidate(_ itemId: ItemID) {
        guard !hasAnyInflight(itemId) else { return }
        overrides.removeValue(forKey: itemId)
    }

    /// Discard all overrides and in-flight tracking (e.g. on disconnect).
    func invalidateAll() {
        overrides.removeAll()
        inflightCounts.removeAll()
    }

    // MARK: - In-flight Tracking (Private)

    /// Upper bound on retained overrides.
    ///
    /// An entry is added for every item the user favourites, marks played, or
    /// finishes watching, and `rebase` only drops one when it exactly matches
    /// fresh server data — so without a cap the dictionary grows for the life of
    /// the process.
    private static let maxOverrides = 500

    /// Drop the oldest overrides once the store exceeds ``maxOverrides``.
    ///
    /// Only entries with no in-flight mutation are evicted; an evicted item
    /// simply falls back to its server value at the next read.
    private func evictOverridesIfNeeded() {
        guard overrides.count > Self.maxOverrides else { return }
        let evictable = overrides.keys.filter { !hasAnyInflight($0) }
        let excess = overrides.count - Self.maxOverrides
        for itemId in evictable.prefix(excess) {
            overrides.removeValue(forKey: itemId)
        }
    }

    private func markInflight(_ itemId: ItemID, _ field: MutationField) {
        inflightCounts[itemId, default: [:]][field, default: 0] += 1
    }

    private func unmarkInflight(_ itemId: ItemID, _ field: MutationField) {
        inflightCounts[itemId, default: [:]][field, default: 0] -= 1
        if inflightCounts[itemId]?[field] ?? 0 <= 0 {
            inflightCounts[itemId]?.removeValue(forKey: field)
        }
        if inflightCounts[itemId]?.isEmpty == true {
            inflightCounts.removeValue(forKey: itemId)
        }
    }

    private func isInflight(_ itemId: ItemID, _ field: MutationField) -> Bool {
        (inflightCounts[itemId]?[field] ?? 0) > 0
    }

    private func hasAnyInflight(_ itemId: ItemID) -> Bool {
        guard let fields = inflightCounts[itemId] else { return false }
        return fields.values.contains { $0 > 0 }
    }
}
