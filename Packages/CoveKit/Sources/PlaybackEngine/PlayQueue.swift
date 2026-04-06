import Foundation
import Models

/// Controls how the queue repeats playback.
public enum RepeatMode: Sendable, Codable {
    /// No repeat — stop after the last track.
    case off
    /// Repeat the entire queue.
    case all
    /// Repeat the current track.
    case one
}

/// Observable play queue that manages track ordering, shuffle, and repeat.
@Observable
@MainActor
public final class PlayQueue {
    // MARK: - State

    public private(set) var tracks: [Track] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var context: PlayContext?
    public var shuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .off

    /// Original track order before shuffle was applied.
    private var originalOrder: [Track] = []

    // MARK: - Computed Properties

    /// The currently selected track, or `nil` if the queue is empty.
    public var currentTrack: Track? {
        guard !tracks.isEmpty, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    /// Whether there is a next track available (considering repeat mode).
    public var hasNext: Bool {
        guard !tracks.isEmpty else { return false }
        if repeatMode == .one || repeatMode == .all { return true }
        return currentIndex < tracks.count - 1
    }

    /// Whether there is a previous track available (considering repeat mode).
    public var hasPrevious: Bool {
        guard !tracks.isEmpty else { return false }
        if repeatMode == .all { return true }
        return currentIndex > 0
    }

    /// The tracks that come after the current track.
    public var upNext: [Track] {
        let nextIndex = currentIndex + 1
        guard nextIndex < tracks.count else { return [] }
        return Array(tracks[nextIndex...])
    }

    // MARK: - Init

    public init() {}

    // MARK: - Queue Operations

    /// Load a new set of tracks and begin at the specified index.
    public func load(tracks: [Track], startingAt index: Int = 0, context: PlayContext? = nil) {
        self.originalOrder = tracks
        self.tracks = tracks
        self.currentIndex = tracks.isEmpty ? 0 : min(index, tracks.count - 1)
        self.context = context

        if shuffleEnabled {
            applyShuffle()
        }
    }

    /// Advance to the next track according to the current repeat mode.
    /// Returns the new current track, or `nil` if at the end without repeat.
    /// Used for automatic track-end advancement.
    @discardableResult
    public func advance() -> Track? {
        guard !tracks.isEmpty else { return nil }

        switch repeatMode {
        case .one:
            // Stay on the same track for automatic advancement
            return tracks[currentIndex]
        case .all:
            currentIndex = (currentIndex + 1) % tracks.count
            return tracks[currentIndex]
        case .off:
            guard currentIndex < tracks.count - 1 else { return nil }
            currentIndex += 1
            return tracks[currentIndex]
        }
    }

    /// Force-advance to the next track, ignoring repeat-one.
    /// Used for user-initiated skip (next button).
    @discardableResult
    public func forceAdvance() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if currentIndex < tracks.count - 1 {
            currentIndex += 1
        } else if repeatMode != .off {
            // Wrap around for repeat-all or repeat-one
            currentIndex = 0
        } else {
            return nil
        }

        return tracks[currentIndex]
    }

    /// Go back to the previous track according to the current repeat mode.
    /// Returns the new current track, or `nil` if at the beginning without repeat.
    @discardableResult
    public func goBack() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = tracks.count - 1
        } else {
            return nil
        }

        return tracks[currentIndex]
    }

    /// Force go back to the previous track, ignoring repeat-one.
    /// Used for user-initiated skip (previous button).
    @discardableResult
    public func forceGoBack() -> Track? {
        guard !tracks.isEmpty else { return nil }

        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode != .off {
            currentIndex = tracks.count - 1
        } else {
            return nil
        }

        return tracks[currentIndex]
    }

    /// Insert a track immediately after the current track.
    public func addNext(_ track: Track) {
        let insertIndex = min(currentIndex + 1, tracks.count)
        tracks.insert(track, at: insertIndex)
        originalOrder.append(track)
    }

    /// Append a track to the end of the queue.
    public func addToEnd(_ track: Track) {
        tracks.append(track)
        originalOrder.append(track)
    }

    /// Remove the track at the given index.
    public func remove(at index: Int) {
        guard tracks.indices.contains(index) else { return }

        let removed = tracks.remove(at: index)
        originalOrder.removeAll { $0.id == removed.id }

        // Adjust current index
        if tracks.isEmpty {
            currentIndex = 0
        } else if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, tracks.count - 1)
        }
    }

    /// Move a track from one position to another.
    public func move(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source),
            tracks.indices.contains(destination),
            source != destination
        else { return }

        let track = tracks.remove(at: source)
        tracks.insert(track, at: destination)

        // Adjust current index to follow the currently playing track
        if source == currentIndex {
            currentIndex = destination
        } else if source < currentIndex && destination >= currentIndex {
            currentIndex -= 1
        } else if source > currentIndex && destination <= currentIndex {
            currentIndex += 1
        }
    }

    /// Toggle shuffle on/off. When enabling, shuffles tracks keeping the current track first.
    /// When disabling, restores the original order.
    public func toggleShuffle() {
        shuffleEnabled.toggle()

        if shuffleEnabled {
            applyShuffle()
        } else {
            restoreOriginalOrder()
        }
    }

    /// Cycle through repeat modes: off → all → one → off.
    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// Clear all tracks and reset state.
    public func clear() {
        tracks = []
        originalOrder = []
        currentIndex = 0
        context = nil
    }

    // MARK: - Private

    /// Shuffle tracks, keeping the current track at the front.
    private func applyShuffle() {
        guard let current = currentTrack else { return }
        var remaining = tracks
        remaining.remove(at: currentIndex)
        remaining.shuffle()
        tracks = [current] + remaining
        currentIndex = 0
    }

    /// Restore original track order, keeping the current track selected.
    private func restoreOriginalOrder() {
        guard let current = currentTrack else { return }
        tracks = originalOrder
        currentIndex = tracks.firstIndex(where: { $0.id == current.id }) ?? 0
    }
}
