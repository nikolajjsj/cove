import Foundation

/// Metadata for an offline-available media item, persisted as a JSON blob.
///
/// **Forward compatibility rules:**
/// 1. Every field except identifiers is optional — missing keys decode as `nil`
/// 2. Never make a previously-optional field required
/// 3. Never rename a coding key
/// 4. New fields are always added as optionals
public struct OfflineMediaMetadata: Codable, Hashable, Sendable {
    // MARK: - Identifiers (required)
    public let itemId: String
    public let serverId: String
    public let mediaType: String  // Raw string for flexible decoding

    // MARK: - Common fields (from MediaItem)
    public var title: String?
    public var overview: String?
    public var genres: [String]?
    public var productionYear: Int?
    public var runTimeTicks: Int64?
    public var communityRating: Double?
    public var officialRating: String?
    public var criticRating: Double?
    public var dateAdded: Date?

    // MARK: - User data
    public var isFavorite: Bool?
    public var playbackPosition: Double?  // TimeInterval
    public var playCount: Int?
    public var isPlayed: Bool?

    // MARK: - Episode-specific
    public var seriesId: String?
    public var seasonId: String?
    public var episodeNumber: Int?
    public var seasonNumber: Int?
    public var seriesName: String?

    // MARK: - Series-specific
    public var status: String?
    public var seasonCount: Int?
    public var episodeCount: Int?

    // MARK: - Album-specific
    public var artistId: String?
    public var artistName: String?
    public var genre: String?
    public var trackCount: Int?
    public var duration: Double?  // TimeInterval

    // MARK: - Track-specific
    public var albumId: String?
    public var albumName: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var codec: String?

    // MARK: - Offline asset paths (relative to downloads directory)
    public var primaryImagePath: String?
    public var backdropImagePath: String?
    public var subtitles: [OfflineSubtitle]?

    public init(
        itemId: String,
        serverId: String,
        mediaType: String,
        title: String? = nil,
        overview: String? = nil,
        genres: [String]? = nil,
        productionYear: Int? = nil,
        runTimeTicks: Int64? = nil,
        communityRating: Double? = nil,
        officialRating: String? = nil,
        criticRating: Double? = nil,
        dateAdded: Date? = nil,
        isFavorite: Bool? = nil,
        playbackPosition: Double? = nil,
        playCount: Int? = nil,
        isPlayed: Bool? = nil,
        seriesId: String? = nil,
        seasonId: String? = nil,
        episodeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        seriesName: String? = nil,
        status: String? = nil,
        seasonCount: Int? = nil,
        episodeCount: Int? = nil,
        artistId: String? = nil,
        artistName: String? = nil,
        genre: String? = nil,
        trackCount: Int? = nil,
        duration: Double? = nil,
        albumId: String? = nil,
        albumName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        codec: String? = nil,
        primaryImagePath: String? = nil,
        backdropImagePath: String? = nil,
        subtitles: [OfflineSubtitle]? = nil
    ) {
        self.itemId = itemId
        self.serverId = serverId
        self.mediaType = mediaType
        self.title = title
        self.overview = overview
        self.genres = genres
        self.productionYear = productionYear
        self.runTimeTicks = runTimeTicks
        self.communityRating = communityRating
        self.officialRating = officialRating
        self.criticRating = criticRating
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.playbackPosition = playbackPosition
        self.playCount = playCount
        self.isPlayed = isPlayed
        self.seriesId = seriesId
        self.seasonId = seasonId
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.seriesName = seriesName
        self.status = status
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.artistId = artistId
        self.artistName = artistName
        self.genre = genre
        self.trackCount = trackCount
        self.duration = duration
        self.albumId = albumId
        self.albumName = albumName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.codec = codec
        self.primaryImagePath = primaryImagePath
        self.backdropImagePath = backdropImagePath
        self.subtitles = subtitles
    }
}

// MARK: - OfflineSubtitle

/// Metadata for a locally-stored subtitle file.
public struct OfflineSubtitle: Codable, Hashable, Sendable {
    public let index: Int
    public let language: String?
    public let title: String?
    public let localPath: String  // Relative path under downloads directory

    public init(index: Int, language: String? = nil, title: String? = nil, localPath: String) {
        self.index = index
        self.language = language
        self.title = title
        self.localPath = localPath
    }
}

// MARK: - Convenience Builders

extension OfflineMediaMetadata {
    /// Create metadata from a `MediaItem`.
    public static func from(
        item: MediaItem,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: item.id.rawValue,
            serverId: serverId,
            mediaType: item.mediaType.rawValue,
            title: item.title,
            overview: item.overview,
            genres: item.genres,
            productionYear: item.productionYear,
            runTimeTicks: item.runTimeTicks,
            communityRating: item.communityRating,
            officialRating: item.officialRating,
            criticRating: item.criticRating,
            dateAdded: item.dateAdded,
            isFavorite: item.userData?.isFavorite,
            playbackPosition: item.userData?.playbackPosition,
            playCount: item.userData?.playCount,
            isPlayed: item.userData?.isPlayed
        )
    }

    /// Create metadata from an `Episode` and its parent identifiers.
    public static func from(
        episode: Episode,
        seriesName: String?,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: episode.id.rawValue,
            serverId: serverId,
            mediaType: MediaType.episode.rawValue,
            title: episode.title,
            overview: episode.overview,
            runTimeTicks: episode.runtime.map { Int64($0 * 10_000_000) },
            seriesId: episode.seriesId?.rawValue,
            seasonId: episode.seasonId?.rawValue,
            episodeNumber: episode.episodeNumber,
            seasonNumber: episode.seasonNumber,
            seriesName: seriesName
        )
    }

    /// Create metadata from a `Track` and its parent identifiers.
    public static func from(
        track: Track,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: track.id.rawValue,
            serverId: serverId,
            mediaType: MediaType.track.rawValue,
            title: track.title,
            artistId: track.artistId?.rawValue,
            artistName: track.artistName,
            duration: track.duration,
            albumId: track.albumId?.rawValue,
            albumName: track.albumName,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            codec: track.codec
        )
    }

    /// Create metadata from an `Album`.
    public static func from(
        album: Album,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: album.id.rawValue,
            serverId: serverId,
            mediaType: MediaType.album.rawValue,
            title: album.title,
            productionYear: album.year,
            artistId: album.artistId?.rawValue,
            artistName: album.artistName,
            genre: album.genre,
            trackCount: album.trackCount,
            duration: album.duration
        )
    }

    /// Create metadata from a `Series`.
    public static func from(
        series: Series,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: series.id.rawValue,
            serverId: serverId,
            mediaType: MediaType.series.rawValue,
            title: series.title,
            overview: series.overview,
            genres: series.genres,
            productionYear: series.year,
            status: series.status,
            seasonCount: series.seasonCount,
            episodeCount: series.episodeCount
        )
    }

    /// Create metadata from a `Season`.
    public static func from(
        season: Season,
        serverId: String
    ) -> OfflineMediaMetadata {
        OfflineMediaMetadata(
            itemId: season.id.rawValue,
            serverId: serverId,
            mediaType: MediaType.season.rawValue,
            title: season.title,
            seriesId: season.seriesId.rawValue,
            seasonNumber: season.seasonNumber,
            episodeCount: season.episodeCount
        )
    }
}
