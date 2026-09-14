import Foundation

/// The pure arithmetic of a reconcile pass. Values in, values out, no I/O — so it
/// is tested with sets, and the mutation tests in the spec have something to bite.
public enum Reconciliation {
    public struct Outcome: Equatable, Sendable {
        /// Ids the server lists that the catalogue lacks. Offset paging skipped them.
        public let missing: [String]
        /// Ids the catalogue holds that the server no longer lists. Deleted upstream.
        public let phantoms: [String]
    }

    /// Both directions in one pass. Deltas cannot report deletions and offset paging
    /// can skip rows; this is the single mechanism that repairs both.
    public static func diff(server: Set<String>, local: Set<String>) -> Outcome {
        Outcome(
            missing: server.subtracting(local).sorted(),
            phantoms: local.subtracting(server).sorted())
    }
}

/// How far back a delta reaches behind its cursor.
///
/// The cursor is a one-second `Date` header read *after* the server planned the
/// query. Two minutes of overlap costs a handful of duplicate upserts and buys
/// immunity to both the precision loss and the ordering.
public enum CursorPolicy {
    public static let overlap: TimeInterval = 120

    public static func since(cursor: Date) -> Date {
        cursor.addingTimeInterval(-overlap)
    }

    /// A delta this large means the catalogue moved too much to trust an offset walk
    /// over the changed set; the engine bootstraps the library instead.
    public static let rebootstrapThreshold = 5_000
}
