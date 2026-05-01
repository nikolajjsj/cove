import Foundation

public enum AppError: Error, LocalizedError, Sendable {
    case networkUnavailable
    case serverUnreachable(url: URL)
    case authExpired(serverName: String)
    case authFailed(reason: String)
    case playbackFailed(reason: String)
    case downloadFailed(itemTitle: String, reason: String)
    case storageFull
    case itemNotFound(id: ItemID)
    case serverError(statusCode: Int, message: String?)
    case unknown(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No network connection available."
        case .serverUnreachable(let url):
            return "Unable to reach server at \(url.absoluteString)."
        case .authExpired(let serverName):
            return "Your session on \(serverName) has expired. Please log in again."
        case .authFailed(let reason):
            return "Authentication failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        case .downloadFailed(let itemTitle, let reason):
            return "Download of \"\(itemTitle)\" failed: \(reason)"
        case .storageFull:
            return "Not enough storage space available."
        case .itemNotFound(let id):
            return "Item not found: \(id.rawValue)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message ?? "Unknown error")"
        case .unknown(let underlying):
            return "An unexpected error occurred: \(underlying.localizedDescription)"
        }
    }

    // Implement Equatable manually since `any Error` isn't Equatable
    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.serverUnreachable(let a), .serverUnreachable(let b)):
            return a == b
        case (.authExpired(let a), .authExpired(let b)):
            return a == b
        case (.authFailed(let a), .authFailed(let b)):
            return a == b
        case (.playbackFailed(let a), .playbackFailed(let b)):
            return a == b
        case (.downloadFailed(let a1, let a2), .downloadFailed(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.storageFull, .storageFull):
            return true
        case (.itemNotFound(let a), .itemNotFound(let b)):
            return a == b
        case (.serverError(let a1, let a2), .serverError(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.unknown, .unknown):
            return lhs.localizedDescription == rhs.localizedDescription
        default:
            return false
        }
    }
}

// Make Hashable for use in identifiable contexts
extension AppError: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .networkUnavailable:
            hasher.combine(0)
        case .serverUnreachable(let url):
            hasher.combine(1)
            hasher.combine(url)
        case .authExpired(let serverName):
            hasher.combine(2)
            hasher.combine(serverName)
        case .authFailed(let reason):
            hasher.combine(3)
            hasher.combine(reason)
        case .playbackFailed(let reason):
            hasher.combine(4)
            hasher.combine(reason)
        case .downloadFailed(let itemTitle, let reason):
            hasher.combine(5)
            hasher.combine(itemTitle)
            hasher.combine(reason)
        case .storageFull:
            hasher.combine(6)
        case .itemNotFound(let id):
            hasher.combine(7)
            hasher.combine(id)
        case .serverError(let statusCode, let message):
            hasher.combine(8)
            hasher.combine(statusCode)
            hasher.combine(message)
        case .unknown:
            hasher.combine(9)
            hasher.combine(localizedDescription)
        }
    }
}
