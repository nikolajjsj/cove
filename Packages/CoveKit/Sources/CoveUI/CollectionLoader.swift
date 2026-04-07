import Foundation
import Observation

/// An `@Observable` model that manages the lifecycle of fetching a collection
/// of items asynchronously.
///
/// Views own an instance via `@State` and switch on `phase` in their body.
/// The fetch closure is provided at the call-site (not init) so it always
/// captures current values from the view's scope.
///
/// ```swift
/// @State private var loader = CollectionLoader<MediaItem>()
///
/// // In body:
/// switch loader.phase { ... }
///
/// // In .task:
/// await loader.load {
///     try await provider.items(in: library, sort: sort, filter: filter)
/// }
/// ```
@MainActor
@Observable
public final class CollectionLoader<Element: Sendable> {

    /// The discrete states of a collection fetch.
    ///
    /// Using an enum instead of separate `isLoading` / `errorMessage` / `items`
    /// booleans prevents impossible state combinations and gives callers an
    /// exhaustive `switch`.
    public enum Phase: Sendable {
        /// A fetch is in progress (also the initial state).
        case loading

        /// The fetch threw a non-cancellation error.
        case failed(String)

        /// The fetch succeeded but the collection was empty.
        case empty

        /// The fetch succeeded with at least one element.
        case loaded([Element])
    }

    // MARK: - Published State

    /// The current phase. Drive your view's body off this via `switch loader.phase`.
    public private(set) var phase: Phase = .loading

    // MARK: - Convenience Accessors

    /// Returns the loaded items, or `[]` in any other phase.
    public var items: [Element] {
        guard case .loaded(let items) = phase else { return [] }
        return items
    }

    /// Whether the loader is currently in the `.loading` phase.
    public var isLoading: Bool {
        guard case .loading = phase else { return false }
        return true
    }

    /// The error message if in `.failed`, otherwise `nil`.
    public var errorMessage: String? {
        guard case .failed(let message) = phase else { return nil }
        return message
    }

    // MARK: - Init

    /// Creates a loader in the `.loading` phase.
    ///
    /// Marked `nonisolated` so `@State` can call it from a nonisolated `View.init`.
    nonisolated public init() {}

    // MARK: - Actions

    /// Performs a fetch, transitioning through `.loading` → `.loaded` / `.empty` / `.failed`.
    ///
    /// - Parameter fetch: An async throwing closure that returns the collection.
    ///   Post-fetch transforms (sort, filter, map) belong inside this closure.
    ///
    /// Cancellation is handled silently — if the enclosing `Task` is cancelled
    /// (e.g. by `.task(id:)` re-firing or navigation popping), the phase is left
    /// unchanged so the user never sees a "The operation was cancelled" error.
    public func load(_ fetch: @Sendable () async throws -> [Element]) async {
        // Stale-while-revalidate: if we already have data, skip the loading
        // spinner and fetch silently in the background.
        let hasExistingData: Bool
        switch phase {
        case .loaded, .empty:
            hasExistingData = true
        default:
            hasExistingData = false
            phase = .loading
        }

        do {
            let result = try await fetch()
            guard !Task.isCancelled else { return }
            phase = result.isEmpty ? .empty : .loaded(result)
        } catch is CancellationError {
            // The task was cancelled (e.g. view torn down or .task(id:) changed).
            // Leave phase as-is — a new load is likely already in-flight.
            return
        } catch {
            guard !Task.isCancelled else { return }
            // During a SWR re-fetch, keep the existing data visible instead
            // of flashing an error the user can't act on.
            if !hasExistingData {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Synchronously transitions to `.failed` without performing a fetch.
    ///
    /// Use for pre-validation when a required parameter is missing:
    /// ```swift
    /// guard let library else { return loader.fail("No music library available.") }
    /// ```
    public func fail(_ message: String) {
        phase = .failed(message)
    }

    /// Resets the loader to its initial `.loading` phase.
    public func reset() {
        phase = .loading
    }
}
