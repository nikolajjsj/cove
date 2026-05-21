// MARK: - Stable Action Wrapper

/// A callback wrapper that prevents closures from causing SwiftUI view invalidation.
///
/// Closures can't be compared for equality, so passing them directly as view
/// parameters causes SwiftUI to re-render the child view on every parent evaluation.
/// This wrapper always compares as equal, telling SwiftUI the callback hasn't changed.
struct StableAction: Equatable {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    func callAsFunction() {
        perform()
    }

    static func == (lhs: StableAction, rhs: StableAction) -> Bool {
        true  // Closures can't be compared; treat as always equal to prevent re-renders
    }
}
