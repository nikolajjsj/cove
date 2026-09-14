import Foundation
import Models

/// Every failure a pass can hit, sorted by what should happen next. The engine
/// never advances a cursor past data it did not commit, so classification only
/// decides *retry, stop, or drop* — never correctness.
public enum SyncErrorClass: Equatable, Sendable {
    /// Weather. Keep the cursor, back off, try again.
    case transient
    /// 401. Stop; the user has to sign in again. Cursors untouched.
    case auth
    /// 404 on one item. Drop that item, continue the pass.
    case permanentItem
    /// 400 or a decoding failure. We sent something wrong. Stop and log; this is a bug.
    case permanentPass

    public static func classify(_ error: any Error) -> SyncErrorClass {
        if error is CancellationError { return .transient }
        guard let appError = error as? AppError else { return .transient }
        switch appError {
        case .networkUnavailable, .serverUnreachable:
            return .transient
        case .authExpired, .authFailed:
            return .auth
        case .itemNotFound:
            return .permanentItem
        case .serverError(let status, _):
            switch status {
            case 404: return .permanentItem
            case 400, 422: return .permanentPass
            case 429, 500...599: return .transient
            default: return .transient
            }
        case .unknown(let underlying):
            // A decoding failure surfaces as .unknown; retrying will not change it.
            return underlying is DecodingError ? .permanentPass : .transient
        case .playbackFailed, .downloadFailed, .storageFull:
            return .transient
        }
    }
}
