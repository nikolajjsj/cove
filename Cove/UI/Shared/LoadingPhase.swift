import SwiftUI

// MARK: - LoadingPhase

/// Represents the lifecycle of an asynchronous data load, modeled after
/// SwiftUI's `AsyncImagePhase`.
///
/// Views declare `@State private var phase: LoadingPhase<MyType> = .loading`
/// and switch on it in their body to render each state. The companion
/// `.asyncContent(_:load:)` modifier drives transitions automatically.
public enum LoadingPhase<Value: Sendable>: Sendable {
    /// The load has not yet completed. This is the initial value.
    case loading

    /// The load completed successfully with the associated value.
    case loaded(Value)

    /// The load failed with the associated error.
    case failed(Error)
}

// MARK: - Convenience Accessors

extension LoadingPhase {
    /// The successfully loaded value, or `nil` if still loading or failed.
    public var value: Value? {
        guard case .loaded(let v) = self else { return nil }
        return v
    }

    /// The error from a failed load, or `nil` if loading or loaded.
    public var error: Error? {
        guard case .failed(let e) = self else { return nil }
        return e
    }

    /// Whether the phase is currently `.loading`.
    public var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }
}

// MARK: - Collection Helpers

extension LoadingPhase where Value: Collection {
    /// Whether the load completed successfully but returned an empty collection.
    ///
    /// Useful for distinguishing "loaded with no results" from "still loading":
    /// ```
    /// case .loaded(let items) where phase.isEmpty:
    ///     ContentUnavailableView("No Items", …)
    /// ```
    public var isEmpty: Bool {
        guard case .loaded(let v) = self else { return false }
        return v.isEmpty
    }
}

// MARK: - AsyncContentModifier

/// A `ViewModifier` that manages the async-load lifecycle for a single
/// `LoadingPhase` binding.
///
/// - Runs `load` inside a `.task(id:)`, transitioning through
///   `.loading` → `.loaded(value)` or `.failed(error)`.
/// - Optionally installs `.refreshable` that re-executes the same `load`
///   closure **without** transitioning through `.loading` (the existing
///   content stays visible during pull-to-refresh, per platform convention).
/// - Respects cooperative cancellation — if the task is cancelled (e.g. the
///   `id` changed or the view disappeared), the phase is not updated.
private struct AsyncContentModifier<Value: Sendable, TaskID: Equatable & Sendable>: ViewModifier {
    @Binding var phase: LoadingPhase<Value>
    let id: TaskID
    let isRefreshable: Bool
    let load: @Sendable () async throws -> Value

    func body(content: Content) -> some View {
        content
            .task(id: id) {
                await performInitialLoad()
            }
            .modifier(
                ConditionalRefreshable(
                    enabled: isRefreshable,
                    action: performRefresh
                )
            )
    }

    // MARK: - Load Implementations

    /// Initial / re-triggered load: transitions through `.loading`.
    private func performInitialLoad() async {
        phase = .loading
        do {
            let result = try await load()
            guard !Task.isCancelled else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            // Task was replaced (id changed) or view disappeared — leave phase as-is.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error)
        }
    }

    /// Refresh load: does **not** set `.loading` so the existing content
    /// remains visible while the refresh spinner is active.
    private func performRefresh() async {
        do {
            let result = try await load()
            guard !Task.isCancelled else { return }
            phase = .loaded(result)
        } catch is CancellationError {
            // Silently ignore — the refresh was cancelled.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error)
        }
    }
}

/// Conditionally applies `.refreshable` so we don't pay the type-erasure
/// cost when it's not requested.
private struct ConditionalRefreshable: ViewModifier {
    let enabled: Bool
    let action: () async -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {

    /// Attaches an async loading lifecycle to this view.
    ///
    /// The modifier runs `load` when the view appears and writes the result
    /// into `phase`. The view body can `switch` on `phase` to render each
    /// state.
    ///
    /// ```swift
    /// @State private var phase: LoadingPhase<[Album]> = .loading
    ///
    /// var body: some View {
    ///     Group {
    ///         switch phase {
    ///         case .loading:
    ///             ProgressView()
    ///         case .loaded(let albums):
    ///             AlbumGrid(albums: albums)
    ///         case .failed(let error):
    ///             ErrorView(error: error)
    ///         }
    ///     }
    ///     .asyncContent($phase) {
    ///         try await provider.fetchAlbums()
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - phase: A binding to the `LoadingPhase` that the modifier drives.
    ///   - refreshable: When `true`, also installs `.refreshable` using the
    ///     same `load` closure. Defaults to `false`.
    ///   - load: An async throwing closure that produces the loaded value.
    ///     Post-fetch transforms (sort, filter, map) belong here.
    func asyncContent<Value: Sendable>(
        _ phase: Binding<LoadingPhase<Value>>,
        refreshable: Bool = false,
        load: @escaping @Sendable () async throws -> Value
    ) -> some View {
        modifier(
            AsyncContentModifier(
                phase: phase,
                id: 0 as Int,
                isRefreshable: refreshable,
                load: load
            )
        )
    }

    /// Attaches an async loading lifecycle to this view, re-triggered whenever
    /// `id` changes (mirrors the semantics of `.task(id:)`).
    ///
    /// Use this overload when the data depends on a changing input such as a
    /// selected library, season, or search query:
    ///
    /// ```swift
    /// .asyncContent($phase, id: library?.id) {
    ///     try await provider.items(in: library!)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - phase: A binding to the `LoadingPhase` that the modifier drives.
    ///   - id: An equatable value whose changes re-trigger the load. The
    ///     previous in-flight task is cancelled automatically.
    ///   - refreshable: When `true`, also installs `.refreshable`.
    ///   - load: An async throwing closure that produces the loaded value.
    func asyncContent<Value: Sendable, ID: Equatable & Sendable>(
        _ phase: Binding<LoadingPhase<Value>>,
        id: ID,
        refreshable: Bool = false,
        load: @escaping @Sendable () async throws -> Value
    ) -> some View {
        modifier(
            AsyncContentModifier(
                phase: phase,
                id: id,
                isRefreshable: refreshable,
                load: load
            )
        )
    }
}
