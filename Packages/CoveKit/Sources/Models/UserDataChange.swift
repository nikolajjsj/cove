import Foundation

/// One user-data edit the user made, to be applied locally now and sent to the
/// server when it can be reached.
///
/// Three fields, because that is what the UI exposes. Each carries the moment it
/// happened on the device clock: the server records *when* something was watched,
/// not when the phone reconnected.
public enum UserDataChange: Hashable, Sendable {
    case played(Bool, at: Date)
    case favorite(Bool, at: Date)
    /// A playback position. `played` is whether the completion threshold was
    /// crossed, decided on the device because offline nobody else can.
    case position(ticks: Int64, played: Bool, at: Date)

    /// The outbox coalesces on this: at most one pending row per (item, field).
    public var field: String {
        switch self {
        case .played: return "played"
        case .favorite: return "favorite"
        case .position: return "position"
        }
    }

    public var occurredAt: Date {
        switch self {
        case .played(_, let at), .favorite(_, let at), .position(_, _, let at): return at
        }
    }

    // MARK: JSON for the `value` column

    private struct Payload: Codable {
        var bool: Bool?
        var ticks: Int64?
        var played: Bool?
        var at: Date
    }

    public var encodedValue: String {
        let payload: Payload
        switch self {
        case .played(let v, let at): payload = Payload(bool: v, at: at)
        case .favorite(let v, let at): payload = Payload(bool: v, at: at)
        case .position(let ticks, let played, let at): payload = Payload(ticks: ticks, played: played, at: at)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try! encoder.encode(payload), as: UTF8.self)
    }

    public init?(field: String, encodedValue: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: Data(encodedValue.utf8)) else { return nil }
        switch field {
        case "played": guard let b = payload.bool else { return nil }; self = .played(b, at: payload.at)
        case "favorite": guard let b = payload.bool else { return nil }; self = .favorite(b, at: payload.at)
        case "position":
            guard let t = payload.ticks else { return nil }
            self = .position(ticks: t, played: payload.played ?? false, at: payload.at)
        default: return nil
        }
    }
}

/// A pending outbox row as the flusher sees it.
public struct PendingUserDataChange: Identifiable, Hashable, Sendable {
    public let id: String
    public let itemId: String
    public let change: UserDataChange
    public let attempts: Int

    public init(id: String, itemId: String, change: UserDataChange, attempts: Int) {
        self.id = id
        self.itemId = itemId
        self.change = change
        self.attempts = attempts
    }
}
