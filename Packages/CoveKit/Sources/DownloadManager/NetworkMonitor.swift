import Foundation
import Models
import Network
import os

/// A lightweight wrapper around `NWPathMonitor` that exposes current connectivity
/// state and an `AsyncStream` of connectivity changes.
///
/// Usage:
/// ```
/// NetworkMonitor.shared.start()
/// for await isConnected in NetworkMonitor.shared.connectivityUpdates {
///     print("Connected: \(isConnected)")
/// }
/// ```
///
/// The monitor runs its callback on a dedicated serial dispatch queue. Internal
/// mutable state is protected by `NSLock` so the type is safe to use from any
/// concurrency context.
public final class NetworkMonitor: @unchecked Sendable {

    // MARK: - Shared Instance

    public static let shared = NetworkMonitor()

    // MARK: - Private State

    private let logger = Logger(
        subsystem: AppConstants.bundleIdentifier, category: "NetworkMonitor")

    /// Lock protecting all mutable ivars.
    private let lock = NSLock()

    /// The underlying path monitor. Created lazily in `start()`.
    private var monitor: NWPathMonitor?

    /// Dedicated queue for NWPathMonitor callbacks.
    private let monitorQueue = DispatchQueue(
        label: "\(AppConstants.bundleIdentifier).NetworkMonitor",
        qos: .utility
    )

    /// Current cached path snapshot.
    private var currentPath: NWPath?

    /// Whether the monitor has been started.
    private var isStarted = false

    /// Continuations for all active `connectivityUpdates` streams.
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    // MARK: - Init

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Public API — Connectivity State

    /// Whether the device currently has a network route that is satisfied.
    ///
    /// Returns `false` if the monitor has not been started yet.
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let path = currentPath else { return false }
        return path.status == .satisfied
    }

    /// Whether the current network path uses an expensive interface (e.g. cellular).
    ///
    /// Returns `false` if the monitor has not been started yet.
    public var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isExpensive ?? false
    }

    /// Whether the current network path is constrained (e.g. Low Data Mode).
    public var isConstrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isConstrained ?? false
    }

    // MARK: - Lifecycle

    /// Start monitoring network path changes.
    ///
    /// Calling this multiple times is safe — subsequent calls are no-ops.
    public func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }

        let newMonitor = NWPathMonitor()
        monitor = newMonitor
        isStarted = true
        lock.unlock()

        newMonitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        newMonitor.start(queue: monitorQueue)
        logger.info("Network monitor started")
    }

    /// Stop monitoring network path changes and cancel all active streams.
    public func stop() {
        lock.lock()
        let existingMonitor = monitor
        monitor = nil
        isStarted = false
        currentPath = nil

        // Finish all active continuations
        let activeContinuations = continuations
        continuations.removeAll()
        lock.unlock()

        existingMonitor?.cancel()

        for (_, continuation) in activeContinuations {
            continuation.finish()
        }

        logger.info("Network monitor stopped")
    }

    // MARK: - Async Stream

    /// An `AsyncStream` that yields `true` when the device gains connectivity
    /// and `false` when it loses connectivity.
    ///
    /// Each access to this property produces a new, independent stream. The stream
    /// immediately yields the current connectivity state upon subscription, then
    /// yields subsequent changes.
    ///
    /// The stream finishes when `stop()` is called or the `NetworkMonitor` is
    /// deallocated.
    public var connectivityUpdates: AsyncStream<Bool> {
        let id = UUID()

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            // Register the continuation so future path updates are forwarded
            self.lock.lock()
            self.continuations[id] = continuation
            let connected = self.currentPath?.status == .satisfied
            self.lock.unlock()

            // Yield the current state immediately
            continuation.yield(connected)

            // When the consumer cancels, remove our continuation
            continuation.onTermination = { @Sendable _ in
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    // MARK: - Private

    private func handlePathUpdate(_ path: NWPath) {
        lock.lock()
        let previousConnected = currentPath?.status == .satisfied
        currentPath = path
        let nowConnected = path.status == .satisfied
        let activeContinuations = continuations
        lock.unlock()

        if previousConnected != nowConnected {
            logger.info(
                "Network connectivity changed: \(nowConnected ? "connected" : "disconnected") (expensive: \(path.isExpensive), constrained: \(path.isConstrained))"
            )
        }

        // Notify all active streams
        for (_, continuation) in activeContinuations {
            continuation.yield(nowConnected)
        }
    }
}
