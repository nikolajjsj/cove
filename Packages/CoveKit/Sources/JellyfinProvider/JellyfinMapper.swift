import Foundation
import JellyfinAPI
import Models

/// Maps Jellyfin DTOs to domain models.
enum JellyfinMapper {
    /// Map VirtualFolderInfo to MediaLibrary.
    static func mapLibrary(_ dto: VirtualFolderInfo) -> MediaLibrary? {
        guard let id = dto.itemId, let name = dto.name else { return nil }
        let collectionType = dto.collectionType.flatMap { CollectionType(rawValue: $0) }
        return MediaLibrary(id: ItemID(id), name: name, collectionType: collectionType)
    }

    /// Map BaseItemDto to MediaItem.
    static func mapItem(_ dto: BaseItemDto) -> MediaItem? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let mediaType = mapMediaType(dto.type)
        let userData = dto.userData.map { mapUserData($0) }

        // Parse dateCreated
        let dateAdded = dto.dateCreated.flatMap { parseDate($0) }

        return MediaItem(
            id: ItemID(id),
            title: name,
            overview: dto.overview,
            mediaType: mediaType,
            dateAdded: dateAdded,
            userData: userData
        )
    }

    /// Map Jellyfin item type string to MediaType.
    static func mapMediaType(_ type: String?) -> MediaType {
        switch type?.lowercased() {
        case "movie": return .movie
        case "series": return .series
        case "season": return .season
        case "episode": return .episode
        case "musicalbum": return .album
        case "musicartist", "artist": return .artist
        case "audio": return .track
        case "playlist": return .playlist
        default: return .movie  // fallback
        }
    }

    /// Map BaseItemUserData to UserData.
    static func mapUserData(_ dto: BaseItemUserData) -> UserData {
        let positionTicks = dto.playbackPositionTicks ?? 0
        let positionSeconds = TimeInterval(positionTicks) / 10_000_000.0

        return UserData(
            isFavorite: dto.isFavorite ?? false,
            playbackPosition: positionSeconds,
            playCount: dto.playCount ?? 0,
            isPlayed: dto.played ?? false,
            lastPlayedDate: dto.lastPlayedDate.flatMap { parseDate($0) }
        )
    }

    /// Map ImageType enum to Jellyfin image type string.
    static func imageTypeString(_ type: ImageType) -> String {
        switch type {
        case .primary: return "Primary"
        case .backdrop: return "Backdrop"
        case .thumb: return "Thumb"
        case .logo: return "Logo"
        case .banner: return "Banner"
        case .art: return "Art"
        }
    }

    /// Map SortField to Jellyfin sort string.
    static func sortByString(_ field: SortField) -> String {
        switch field {
        case .name: return "SortName"
        case .dateAdded: return "DateCreated"
        case .dateCreated: return "DateCreated"
        case .datePlayed: return "DatePlayed"
        case .premiereDate: return "PremiereDate"
        case .communityRating: return "CommunityRating"
        case .criticRating: return "CriticRating"
        case .runtime: return "Runtime"
        case .random: return "Random"
        case .albumArtist: return "AlbumArtist"
        case .album: return "Album"
        }
    }

    /// Map SortOrder to Jellyfin sort order string.
    static func sortOrderString(_ order: Models.SortOrder) -> String {
        switch order {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }

    // MARK: - Helpers

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        ]
        return formats.map { format in
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}
