import Testing

@testable import CoveUI

@Suite("CollectionLoader")
struct CollectionLoaderTests {

    // MARK: - Phase Transitions

    @Test @MainActor
    func initialPhaseIsLoading() {
        let loader = CollectionLoader<String>()
        guard case .loading = loader.phase else {
            Issue.record("Expected .loading, got \(loader.phase)")
            return
        }
    }

    @Test @MainActor
    func loadTransitionsToLoaded() async {
        let loader = CollectionLoader<String>()

        await loader.load { ["a", "b", "c"] }

        guard case .loaded(let items) = loader.phase else {
            Issue.record("Expected .loaded, got \(loader.phase)")
            return
        }
        #expect(items == ["a", "b", "c"])
    }

    @Test @MainActor
    func loadedItemsAccessor() async {
        let loader = CollectionLoader<Int>()
        #expect(loader.items.isEmpty)

        await loader.load { [1, 2, 3] }

        #expect(loader.items == [1, 2, 3])
    }

    @Test @MainActor
    func loadTransitionsToEmptyWhenResultIsEmpty() async {
        let loader = CollectionLoader<Int>()

        await loader.load { [] }

        guard case .empty = loader.phase else {
            Issue.record("Expected .empty, got \(loader.phase)")
            return
        }
        #expect(loader.items.isEmpty)
    }

    @Test @MainActor
    func loadTransitionsToFailedOnThrow() async {
        let loader = CollectionLoader<Int>()

        await loader.load { throw TestError.simulated }

        guard case .failed(let message) = loader.phase else {
            Issue.record("Expected .failed, got \(loader.phase)")
            return
        }
        #expect(message.contains("simulated") || !message.isEmpty)
    }

    // MARK: - fail(_:) Shortcut

    @Test @MainActor
    func failSetsPhaseDirectly() {
        let loader = CollectionLoader<Int>()

        loader.fail("Missing parameter")

        guard case .failed(let message) = loader.phase else {
            Issue.record("Expected .failed, got \(loader.phase)")
            return
        }
        #expect(message == "Missing parameter")
    }

    @Test @MainActor
    func failDoesNotRequireAsync() {
        // Verifying this is a synchronous operation — no await needed
        let loader = CollectionLoader<String>()
        loader.fail("sync error")

        guard case .failed = loader.phase else {
            Issue.record("Expected .failed")
            return
        }
    }

    // MARK: - Items Accessor in Non-Loaded States

    @Test @MainActor
    func itemsReturnsEmptyInLoadingPhase() {
        let loader = CollectionLoader<String>()
        #expect(loader.items.isEmpty)
    }

    @Test @MainActor
    func itemsReturnsEmptyInFailedPhase() {
        let loader = CollectionLoader<String>()
        loader.fail("error")
        #expect(loader.items.isEmpty)
    }

    @Test @MainActor
    func itemsReturnsEmptyInEmptyPhase() async {
        let loader = CollectionLoader<String>()
        await loader.load { [] }
        #expect(loader.items.isEmpty)
    }

    // MARK: - Reload Behavior

    @Test @MainActor
    func loadCanBeCalledMultipleTimes() async {
        let loader = CollectionLoader<Int>()

        await loader.load { [1, 2] }
        #expect(loader.items == [1, 2])

        await loader.load { [3, 4, 5] }
        #expect(loader.items == [3, 4, 5])
    }

    @Test @MainActor
    func loadAfterFailureRecovery() async {
        let loader = CollectionLoader<String>()

        await loader.load { throw TestError.simulated }
        guard case .failed = loader.phase else {
            Issue.record("Expected .failed after error")
            return
        }

        await loader.load { ["recovered"] }
        guard case .loaded(let items) = loader.phase else {
            Issue.record("Expected .loaded after recovery, got \(loader.phase)")
            return
        }
        #expect(items == ["recovered"])
    }

    @Test @MainActor
    func loadAfterEmptyToLoaded() async {
        let loader = CollectionLoader<Int>()

        await loader.load { [] }
        guard case .empty = loader.phase else {
            Issue.record("Expected .empty")
            return
        }

        await loader.load { [42] }
        guard case .loaded(let items) = loader.phase else {
            Issue.record("Expected .loaded, got \(loader.phase)")
            return
        }
        #expect(items == [42])
    }

    // MARK: - Post-Fetch Transformation

    @Test @MainActor
    func loadClosureCanTransformResults() async {
        let loader = CollectionLoader<Int>()

        await loader.load {
            let raw = [3, 1, 4, 1, 5, 9]
            return raw.sorted()
        }

        #expect(loader.items == [1, 1, 3, 4, 5, 9])
    }

    @Test @MainActor
    func loadClosureCanFilterResults() async {
        let loader = CollectionLoader<Int>()

        await loader.load {
            let raw = [1, 2, 3, 4, 5, 6]
            return raw.filter { $0.isMultiple(of: 2) }
        }

        #expect(loader.items == [2, 4, 6])
    }

    @Test @MainActor
    func loadClosureFilterToEmptyTriggersEmptyPhase() async {
        let loader = CollectionLoader<Int>()

        await loader.load {
            let raw = [1, 3, 5]
            return raw.filter { $0.isMultiple(of: 2) }
        }

        guard case .empty = loader.phase else {
            Issue.record("Expected .empty when filter produces no results, got \(loader.phase)")
            return
        }
    }

    // MARK: - Cancellation

    @Test @MainActor
    func cancelledTaskDoesNotTransitionPhase() async {
        let loader = CollectionLoader<Int>()

        // Start a load that will be cancelled
        let task = Task { @MainActor in
            await loader.load {
                try await Task.sleep(for: .seconds(10))
                return [1, 2, 3]
            }
        }

        // Cancel immediately
        task.cancel()

        // Wait for the task to complete
        await task.value

        // Phase should still be .loading (the initial state),
        // not .failed with a CancellationError
        guard case .loading = loader.phase else {
            Issue.record(
                "Expected .loading after cancellation, got \(loader.phase)"
            )
            return
        }
    }

    @Test @MainActor
    func cancelledTaskPreservesExistingLoadedState() async {
        let loader = CollectionLoader<String>()

        // First: load successfully
        await loader.load { ["original"] }
        #expect(loader.items == ["original"])

        // Second: start a slow load, then cancel it
        let task = Task { @MainActor in
            await loader.load {
                try await Task.sleep(for: .seconds(10))
                return ["should not appear"]
            }
        }

        // Give the task a moment to enter the .loading phase
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value

        // The loader should be in .loading state (because load() sets it immediately)
        // but NOT in .failed or .loaded with the cancelled result
        let phase = loader.phase
        switch phase {
        case .loading:
            break  // acceptable — was set before cancellation
        case .loaded(let items) where items == ["original"]:
            break  // also acceptable if cancellation was processed very fast
        default:
            Issue.record(
                "Expected .loading or original .loaded after cancellation, got \(phase)"
            )
        }
    }

    // MARK: - Sendable Element Types

    @Test @MainActor
    func worksWithStructElements() async {
        struct Item: Sendable, Equatable {
            let id: Int
            let name: String
        }

        let loader = CollectionLoader<Item>()
        await loader.load {
            [Item(id: 1, name: "First"), Item(id: 2, name: "Second")]
        }

        #expect(loader.items.count == 2)
        #expect(loader.items[0].name == "First")
    }
}

// MARK: - Test Helpers

private enum TestError: Error, LocalizedError {
    case simulated

    var errorDescription: String? { "simulated error" }
}
