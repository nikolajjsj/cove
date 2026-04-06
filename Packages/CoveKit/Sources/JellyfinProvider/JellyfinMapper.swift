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
    static func mapItem(_ dto: BaseItemDto, baseURL: URL? = nil) -> MediaItem? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let mediaType = mapMediaType(dto.type)
        let userData = dto.userData.map { mapUserData($0) }

        // Parse dateCreated
        let dateAdded = dto.dateCreated.flatMap { parseDate($0) }

        // Map people
        let people: [Person]
        if let baseURL, let dtoPersons = dto.people {
            people = dtoPersons.compactMap { mapPerson($0, baseURL: baseURL) }
        } else {
            people = []
        }

        // Map remote trailer URLs
        let remoteTrailerURLs: [URL] = (dto.remoteTrailers ?? []).compactMap { trailer in
            trailer.url.flatMap { URL(string: $0) }
        }

        return MediaItem(
            id: ItemID(id),
            title: name,
            overview: dto.overview,
            mediaType: mediaType,
            dateAdded: dateAdded,
            productionYear: dto.productionYear,
            genres: dto.genres,
            runTimeTicks: dto.runTimeTicks,
            communityRating: dto.communityRating,
            officialRating: dto.officialRating,
            criticRating: dto.criticRating,
            people: people,
            remoteTrailerURLs: remoteTrailerURLs,
            userData: userData
        )
    }

    /// Map BaseItemPerson to Person domain model.
    /// Requires the API client's base URL to construct person image URLs.
    static func mapPerson(_ dto: BaseItemPerson, baseURL: URL) -> Person? {
        guard let id = dto.id, let name = dto.name else { return nil }

        // Construct image URL: /Items/{personId}/Images/Primary
        var imageURL: URL? = nil
        if dto.primaryImageTag != nil {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("Items/\(id)/Images/Primary"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "maxWidth", value: "200"),
                URLQueryItem(name: "maxHeight", value: "200"),
            ]
            if let tag = dto.primaryImageTag {
                components?.queryItems?.append(URLQueryItem(name: "tag", value: tag))
            }
            imageURL = components?.url
        }

        return Person(
            id: ItemID(id),
            name: name,
            role: dto.role,
            type: dto.type,
            imageURL: imageURL
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
        case "boxset": return .collection
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

    // MARK: - Music Mapping

    /// Map BaseItemDto to Artist.
    static func mapArtist(_ dto: BaseItemDto) -> Artist? {
        guard let id = dto.id, let name = dto.name else { return nil }
        return Artist(
            id: ArtistID(id),
            name: name,
            overview: dto.overview,
            sortName: dto.name,
            albumCount: nil
        )
    }

    /// Map BaseItemDto to Album.
    static func mapAlbum(_ dto: BaseItemDto) -> Album? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let artistId = dto.artistItems?.first?.id.map { ArtistID($0) }
        let duration: TimeInterval? = dto.runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
        return Album(
            id: AlbumID(id),
            title: name,
            artistId: artistId,
            artistName: dto.albumArtist,
            year: dto.productionYear,
            genre: dto.genres?.first,
            trackCount: nil,
            duration: duration
        )
    }

    /// Map BaseItemDto to Track.
    static func mapTrack(_ dto: BaseItemDto) -> Track? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let artistId = dto.artistItems?.first?.id.map { ArtistID($0) }
        let artistName = dto.albumArtist ?? dto.artistItems?.first?.name
        let albumId = dto.albumId.map { AlbumID($0) }
        let duration: TimeInterval? = dto.runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
        return Track(
            id: TrackID(id),
            title: name,
            albumId: albumId,
            albumName: dto.album,
            artistId: artistId,
            artistName: artistName,
            trackNumber: dto.indexNumber,
            discNumber: dto.parentIndexNumber,
            duration: duration,
            codec: nil
        )
    }

    /// Map BaseItemDto to Playlist.
    static func mapPlaylist(_ dto: BaseItemDto) -> Playlist? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let duration: TimeInterval? = dto.runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
        return Playlist(
            id: PlaylistID(id),
            name: name,
            overview: dto.overview,
            itemCount: nil,
            duration: duration
        )
    }

    // MARK: - Video Mapping

    /// Map BaseItemDto to Season.
    static func mapSeason(_ dto: BaseItemDto) -> Season? {
        guard let id = dto.id, let name = dto.name else { return nil }
        // seriesId might come from the dto's seriesId field or parentId
        guard let seriesId = dto.seriesId else { return nil }
        return Season(
            id: SeasonID(id),
            seriesId: SeriesID(seriesId),
            seasonNumber: dto.indexNumber ?? 0,
            title: name,
            episodeCount: dto.childCount
        )
    }

    /// Map BaseItemDto to Episode.
    static func mapEpisode(_ dto: BaseItemDto) -> Episode? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let runtime: TimeInterval? = dto.runTimeTicks.map { TimeInterval($0) / 10_000_000.0 }
        return Episode(
            id: EpisodeID(id),
            seriesId: dto.seriesId.map { SeriesID($0) },
            seasonId: dto.seasonId.map { SeasonID($0) },
            episodeNumber: dto.indexNumber,
            seasonNumber: dto.parentIndexNumber,
            title: name,
            overview: dto.overview,
            runtime: runtime
        )
    }

    /// Map MediaStreamInfo DTOs to domain MediaStream models.
    static func mapMediaStreams(_ dtos: [MediaStreamInfo]) -> [MediaStream] {
        dtos.compactMap { dto -> MediaStream? in
            guard let index = dto.index, let codec = dto.codec else { return nil }
            let streamType: MediaStreamType
            switch dto.type?.lowercased() {
            case "video": streamType = .video
            case "audio": streamType = .audio
            case "subtitle": streamType = .subtitle
            default: return nil
            }
            return MediaStream(
                index: index,
                type: streamType,
                codec: codec,
                language: dto.language,
                title: dto.displayTitle ?? dto.title,
                isExternal: dto.isExternal ?? false
            )
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
