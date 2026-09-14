import Foundation

/// What the sync engine is doing right now, for the UI to say so honestly.
///
/// The grid's empty state has to tell "nothing here" apart from "still syncing" and
/// from "couldn't reach the server, showing what we have". These are those three
/// states, plus the quiet one.
public enum CatalogSyncStatus: Equatable, Sendable {
    case idle
    /// First sync of a library is in progress; `done` of `total` items have landed.
    case bootstrapping(libraryName: String, done: Int, total: Int)
    /// A delta or reconcile pass is running.
    case syncing
    /// The last pass failed. The catalogue is still readable; it may be stale.
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .bootstrapping, .syncing: return true
        case .idle, .failed: return false
        }
    }
}
