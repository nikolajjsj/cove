import Foundation
import JellyfinAPI
import MediaServerKit
import Models

extension JellyfinServerProvider: UserDataWriter {
    public func writePlayed(itemId: String, isPlayed: Bool, at date: Date) async throws {
        let (client, userId) = try authenticatedClient()
        if isPlayed {
            try await client.markPlayed(userId: userId, itemId: itemId, datePlayed: date)
        } else {
            try await client.markUnplayed(userId: userId, itemId: itemId)
        }
    }

    public func writeFavorite(itemId: String, isFavorite: Bool) async throws {
        let (client, userId) = try authenticatedClient()
        if isFavorite {
            try await client.addFavorite(userId: userId, itemId: itemId)
        } else {
            try await client.removeFavorite(userId: userId, itemId: itemId)
        }
    }

    public func writePosition(itemId: String, ticks: Int64, played: Bool, at date: Date) async throws {
        let (client, userId) = try authenticatedClient()
        try await client.updateUserData(
            userId: userId, itemId: itemId, positionTicks: ticks, played: played, lastPlayedDate: date)
    }

    public func currentPosition(itemId: String) async throws -> (ticks: Int64, played: Bool) {
        let (client, userId) = try authenticatedClient()
        let ud = try await client.userData(userId: userId, itemId: itemId)
        return (ud.playbackPositionTicks ?? 0, ud.played ?? false)
    }
}
