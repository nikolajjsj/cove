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
        lhs.localizedDescription == rhs.localizedDescription
    }
}

// Make Hashable for use in identifiable contexts
extension AppError: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(localizedDescription)
    }
}
