import Foundation
import MediaServerKit
import Models

// MARK: - UserDataStore

/// Centralized, observable store for per-item user data (favorite, played, etc.)
/// that provides optimistic updates with automatic server synchronization and
/// rollback on failure.
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
    func markPlayed(itemId: ItemID) async throws {
        let base = userData(for: itemId, fallback: nil)
        guard !base.isPlayed else { return }

        // Optimistic update
        var updated = base
        updated.isPlayed = true
        overrides[itemId] = updated
        markInflight(itemId, .played)

        do {
            try await mutationProvider.setPlayed(itemId: itemId, isPlayed: true)
            unmarkInflight(itemId, .played)
        } catch {
            unmarkInflight(itemId, .played)
            if var current = overrides[itemId] {
                current.isPlayed = false
                overrides[itemId] = current
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

        if let runtime, runtime > 0, position / runtime >= 0.9 {
            data.isPlayed = true
            data.playCount += 1
            data.lastPlayedDate = .now
        }

        overrides[itemId] = data
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
