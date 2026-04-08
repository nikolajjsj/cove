import Foundation
import Models
import Testing

@testable import JellyfinAPI
@testable import JellyfinProvider

@Suite("JellyfinMapper")
struct JellyfinMapperTests {

    // MARK: - mapMediaType

    @Suite("mapMediaType")
    struct MapMediaTypeTests {

        @Test("Maps all known type strings")
        func knownTypes() {
            #expect(JellyfinMapper.mapMediaType("Movie") == .movie)
            #expect(JellyfinMapper.mapMediaType("Series") == .series)
            #expect(JellyfinMapper.mapMediaType("Season") == .season)
            #expect(JellyfinMapper.mapMediaType("Episode") == .episode)
            #expect(JellyfinMapper.mapMediaType("MusicAlbum") == .album)
            #expect(JellyfinMapper.mapMediaType("MusicArtist") == .artist)
            #expect(JellyfinMapper.mapMediaType("Artist") == .artist)
            #expect(JellyfinMapper.mapMediaType("Audio") == .track)
            #expect(JellyfinMapper.mapMediaType("Playlist") == .playlist)
            #expect(JellyfinMapper.mapMediaType("BoxSet") == .collection)
            #expect(JellyfinMapper.mapMediaType("Genre") == .genre)
            #expect(JellyfinMapper.mapMediaType("MusicGenre") == .genre)
        }

        @Test("Is case-insensitive")
        func caseInsensitive() {
            #expect(JellyfinMapper.mapMediaType("movie") == .movie)
            #expect(JellyfinMapper.mapMediaType("MOVIE") == .movie)
            #expect(JellyfinMapper.mapMediaType("MoViE") == .movie)
            #expect(JellyfinMapper.mapMediaType("musicalbum") == .album)
            #expect(JellyfinMapper.mapMediaType("MUSICARTIST") == .artist)
        }

        @Test("Unknown type falls back to movie")
        func unknownFallback() {
            #expect(JellyfinMapper.mapMediaType("SomethingNew") == .movie)
            #expect(JellyfinMapper.mapMediaType("") == .movie)
        }

        @Test("Nil type falls back to movie")
        func nilFallback() {
            #expect(JellyfinMapper.mapMediaType(nil) == .movie)
        }
    }

    // MARK: - mapItem

    @Suite("mapItem")
    struct MapItemTests {

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Test")
            #expect(JellyfinMapper.mapItem(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "abc", name: nil)
            #expect(JellyfinMapper.mapItem(dto) == nil)
        }

        @Test("Maps basic fields correctly")
        func basicFields() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test Movie",
                overview: "A great movie",
                type: "Movie",
                productionYear: 2023,
                communityRating: 8.5,
                criticRating: 92.0,
                officialRating: "PG-13",
                runTimeTicks: 72_000_000_000,
                genres: ["Action", "Comedy"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item != nil)
            #expect(item?.id == ItemID("item1"))
            #expect(item?.title == "Test Movie")
            #expect(item?.overview == "A great movie")
            #expect(item?.mediaType == .movie)
            #expect(item?.productionYear == 2023)
            #expect(item?.communityRating == 8.5)
            #expect(item?.criticRating == 92.0)
            #expect(item?.officialRating == "PG-13")
            #expect(item?.runTimeTicks == 72_000_000_000)
            #expect(item?.genres == ["Action", "Comedy"])
        }

        @Test("Maps image tags from Primary, Logo, and Backdrop")
        func imageTags() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                imageTags: ["Primary": "ptag", "Logo": "ltag", "Backdrop": "btag"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.imageTags?[.primary] == "ptag")
            #expect(item?.imageTags?[.logo] == "ltag")
            #expect(item?.imageTags?[.backdrop] == "btag")
        }

        @Test("Maps Thumb, Banner, Art image tags")
        func additionalImageTags() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                imageTags: ["Thumb": "ttag", "Banner": "bntag", "Art": "atag"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.imageTags?[.thumb] == "ttag")
            #expect(item?.imageTags?[.banner] == "bntag")
            #expect(item?.imageTags?[.art] == "atag")
        }

        @Test("Uses backdropImageTags as fallback when Backdrop not in imageTags")
        func backdropFallback() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                imageTags: ["Primary": "ptag"],
                backdropImageTags: ["backdrop_fallback_tag"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.imageTags?[.primary] == "ptag")
            #expect(item?.imageTags?[.backdrop] == "backdrop_fallback_tag")
        }

        @Test("Does not override existing Backdrop with backdropImageTags")
        func backdropNoOverride() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                imageTags: ["Backdrop": "original"],
                backdropImageTags: ["fallback"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.imageTags?[.backdrop] == "original")
        }

        @Test("Returns nil imageTags when dto has no imageTags")
        func noImageTags() {
            let dto = BaseItemDto(id: "item1", name: "Test")
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.imageTags == nil)
        }

        @Test("Maps audio-specific fields")
        func audioFields() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Song",
                type: "Audio",
                albumId: "album1",
                albumArtist: "The Band",
                album: "Greatest Hits",
                artistItems: [NameIdPair(name: "The Band", id: "artist1")]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.artistName == "The Band")
            #expect(item?.albumName == "Greatest Hits")
            #expect(item?.albumId == ItemID("album1"))
        }

        @Test("Maps episode-specific fields")
        func episodeFields() {
            let dto = BaseItemDto(
                id: "ep1",
                name: "Pilot",
                type: "Episode",
                seriesId: "series1",
                seriesName: "Breaking Bad",
                parentIndexNumber: 1,
                indexNumber: 1
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.seriesName == "Breaking Bad")
            #expect(item?.seriesId == ItemID("series1"))
            #expect(item?.indexNumber == 1)
            #expect(item?.parentIndexNumber == 1)
        }

        @Test("Maps userData when present")
        func withUserData() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                userData: BaseItemUserData(
                    isFavorite: true,
                    playbackPositionTicks: 100_000_000,
                    playCount: 5,
                    played: true
                )
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.userData != nil)
            #expect(item?.userData?.isFavorite == true)
            #expect(item?.userData?.isPlayed == true)
        }

        @Test("Maps providerIds")
        func providerIds() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                providerIds: ["Imdb": "tt1234567", "Tmdb": "12345"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.providerIds?.imdb == "tt1234567")
            #expect(item?.providerIds?.tmdb == "12345")
        }

        @Test("Maps studios")
        func studios() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                studios: [
                    StudioDto(name: "Warner Bros", id: "s1"),
                    StudioDto(name: "Universal", id: "s2"),
                ]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.studios == ["Warner Bros", "Universal"])
        }

        @Test("Maps tagline from first taglines entry")
        func tagline() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                taglines: ["Just when you thought it was safe", "Another tagline"]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.tagline == "Just when you thought it was safe")
        }

        @Test("Maps originalTitle")
        func originalTitle() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                originalTitle: "Le Film Original"
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.originalTitle == "Le Film Original")
        }

        @Test("Maps chapters")
        func chapters() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                chapters: [
                    ChapterInfoDto(
                        startPositionTicks: 0,
                        name: "Intro",
                        imagePath: nil,
                        imageTag: "ch0"
                    ),
                    ChapterInfoDto(
                        startPositionTicks: 6_000_000_000,
                        name: "Act 1",
                        imagePath: nil,
                        imageTag: nil
                    ),
                ]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.chapters.count == 2)
            #expect(item?.chapters[0].name == "Intro")
            #expect(item?.chapters[0].startPosition == 0.0)
            #expect(item?.chapters[1].name == "Act 1")
            #expect(item?.chapters[1].startPosition == 600.0)
        }

        @Test("Prefers albumArtist over artistItems for artistName")
        func artistNamePreference() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                albumArtist: "Album Artist",
                artistItems: [NameIdPair(name: "Track Artist", id: "a1")]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.artistName == "Album Artist")
        }

        @Test("Falls back to artistItems name when albumArtist is nil")
        func artistNameFallback() {
            let dto = BaseItemDto(
                id: "item1",
                name: "Test",
                artistItems: [NameIdPair(name: "Track Artist", id: "a1")]
            )
            let item = JellyfinMapper.mapItem(dto)
            #expect(item?.artistName == "Track Artist")
        }
    }

    // MARK: - mapArtist

    @Suite("mapArtist")
    struct MapArtistTests {

        @Test("Maps basic fields")
        func basicMapping() {
            let dto = BaseItemDto(
                id: "artist1",
                name: "Test Artist",
                overview: "A great artist",
                genres: ["Rock", "Pop"]
            )
            let artist = JellyfinMapper.mapArtist(dto)
            #expect(artist != nil)
            #expect(artist?.id == ArtistID("artist1"))
            #expect(artist?.name == "Test Artist")
            #expect(artist?.overview == "A great artist")
            #expect(artist?.sortName == "Test Artist")
            #expect(artist?.genres == ["Rock", "Pop"])
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Test")
            #expect(JellyfinMapper.mapArtist(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "artist1", name: nil)
            #expect(JellyfinMapper.mapArtist(dto) == nil)
        }

        @Test("Maps userData when present")
        func withUserData() {
            let dto = BaseItemDto(
                id: "artist1",
                name: "Test",
                userData: BaseItemUserData(isFavorite: true)
            )
            let artist = JellyfinMapper.mapArtist(dto)
            #expect(artist?.userData?.isFavorite == true)
        }

        @Test("albumCount is always nil from DTO mapping")
        func albumCountNil() {
            let dto = BaseItemDto(id: "artist1", name: "Test")
            let artist = JellyfinMapper.mapArtist(dto)
            #expect(artist?.albumCount == nil)
        }
    }

    // MARK: - mapAlbum

    @Suite("mapAlbum")
    struct MapAlbumTests {

        @Test("Maps basic fields and converts runTimeTicks to seconds")
        func basicMapping() {
            let dto = BaseItemDto(
                id: "album1",
                name: "Test Album",
                productionYear: 2023,
                runTimeTicks: 36_000_000_000,
                genres: ["Rock", "Indie"],
                albumArtist: "The Artist",
                artistItems: [NameIdPair(name: "The Artist", id: "artist1")]
            )
            let album = JellyfinMapper.mapAlbum(dto)
            #expect(album != nil)
            #expect(album?.id == AlbumID("album1"))
            #expect(album?.title == "Test Album")
            #expect(album?.artistId == ArtistID("artist1"))
            #expect(album?.artistName == "The Artist")
            #expect(album?.year == 2023)
            #expect(album?.genre == "Rock")
            #expect(album?.genres == ["Rock", "Indie"])
            #expect(album?.duration == 3600.0)
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Test")
            #expect(JellyfinMapper.mapAlbum(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "album1", name: nil)
            #expect(JellyfinMapper.mapAlbum(dto) == nil)
        }

        @Test("Duration is nil when runTimeTicks is nil")
        func nilDuration() {
            let dto = BaseItemDto(id: "album1", name: "Test")
            let album = JellyfinMapper.mapAlbum(dto)
            #expect(album?.duration == nil)
        }

        @Test("trackCount is always nil from DTO mapping")
        func trackCountNil() {
            let dto = BaseItemDto(id: "album1", name: "Test")
            let album = JellyfinMapper.mapAlbum(dto)
            #expect(album?.trackCount == nil)
        }

        @Test("Maps dateAdded from dateCreated")
        func dateAdded() {
            let dto = BaseItemDto(
                id: "album1",
                name: "Test",
                dateCreated: "2023-06-15T10:30:00.000Z"
            )
            let album = JellyfinMapper.mapAlbum(dto)
            #expect(album?.dateAdded != nil)
        }
    }

    // MARK: - mapTrack

    @Suite("mapTrack")
    struct MapTrackTests {

        @Test("Maps all fields including codec and bitRate from mediaSources")
        func fullMapping() {
            let audioStream = MediaStreamInfo(
                index: 0,
                type: "Audio",
                codec: "flac",
                language: "eng",
                title: nil,
                isExternal: nil,
                isDefault: nil,
                isForced: nil,
                deliveryMethod: nil,
                deliveryUrl: nil,
                displayTitle: nil,
                height: nil,
                width: nil,
                channels: 2,
                bitRate: 320_000,
                sampleRate: 44100,
                videoRange: nil,
                videoRangeType: nil
            )
            let source = MediaSourceInfo(
                id: nil,
                name: nil,
                container: "flac",
                supportsDirectPlay: nil,
                supportsDirectStream: nil,
                supportsTranscoding: nil,
                transcodingUrl: nil,
                mediaStreams: [audioStream],
                bitrate: nil,
                size: nil
            )
            let dto = BaseItemDto(
                id: "track1",
                name: "Test Track",
                runTimeTicks: 30_000_000_000,
                genres: ["Rock"],
                parentIndexNumber: 1,
                indexNumber: 5,
                albumId: "album1",
                albumArtist: "Artist Name",
                album: "Album Name",
                artistItems: [NameIdPair(name: "Artist Name", id: "artist1")],
                mediaSources: [source]
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track != nil)
            #expect(track?.id == TrackID("track1"))
            #expect(track?.title == "Test Track")
            #expect(track?.codec == "flac")
            #expect(track?.bitRate == 320_000)
            #expect(track?.sampleRate == 44100)
            #expect(track?.channelCount == 2)
            #expect(track?.trackNumber == 5)
            #expect(track?.discNumber == 1)
            #expect(track?.albumId == AlbumID("album1"))
            #expect(track?.albumName == "Album Name")
            #expect(track?.artistId == ArtistID("artist1"))
            #expect(track?.artistName == "Artist Name")
            #expect(track?.duration == 3000.0)
            #expect(track?.genres == ["Rock"])
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Test")
            #expect(JellyfinMapper.mapTrack(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "track1", name: nil)
            #expect(JellyfinMapper.mapTrack(dto) == nil)
        }

        @Test("Falls back to container when audio stream has no codec")
        func codecFallbackToContainer() {
            let audioStream = MediaStreamInfo(
                index: 0,
                type: "Audio",
                codec: nil,
                language: nil,
                title: nil,
                isExternal: nil,
                isDefault: nil,
                isForced: nil,
                deliveryMethod: nil,
                deliveryUrl: nil,
                displayTitle: nil,
                height: nil,
                width: nil,
                channels: nil,
                bitRate: nil,
                sampleRate: nil,
                videoRange: nil,
                videoRangeType: nil
            )
            let source = MediaSourceInfo(
                id: nil,
                name: nil,
                container: "mp3",
                supportsDirectPlay: nil,
                supportsDirectStream: nil,
                supportsTranscoding: nil,
                transcodingUrl: nil,
                mediaStreams: [audioStream],
                bitrate: nil,
                size: nil
            )
            let dto = BaseItemDto(
                id: "track1",
                name: "Test",
                mediaSources: [source]
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track?.codec == "mp3")
        }

        @Test("Falls back to source bitrate when audio stream has no bitRate")
        func bitRateFallbackToSource() {
            let audioStream = MediaStreamInfo(
                index: 0,
                type: "Audio",
                codec: "aac",
                language: nil,
                title: nil,
                isExternal: nil,
                isDefault: nil,
                isForced: nil,
                deliveryMethod: nil,
                deliveryUrl: nil,
                displayTitle: nil,
                height: nil,
                width: nil,
                channels: nil,
                bitRate: nil,
                sampleRate: nil,
                videoRange: nil,
                videoRangeType: nil
            )
            let source = MediaSourceInfo(
                id: nil,
                name: nil,
                container: nil,
                supportsDirectPlay: nil,
                supportsDirectStream: nil,
                supportsTranscoding: nil,
                transcodingUrl: nil,
                mediaStreams: [audioStream],
                bitrate: 256_000,
                size: nil
            )
            let dto = BaseItemDto(
                id: "track1",
                name: "Test",
                mediaSources: [source]
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track?.bitRate == 256_000)
        }

        @Test("Prefers albumArtist for artistName over artistItems")
        func artistNamePreference() {
            let dto = BaseItemDto(
                id: "track1",
                name: "Test",
                albumArtist: "Album Artist",
                artistItems: [NameIdPair(name: "Track Artist", id: "a1")]
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track?.artistName == "Album Artist")
        }

        @Test("Falls back to artistItems name when albumArtist is nil")
        func artistNameFallback() {
            let dto = BaseItemDto(
                id: "track1",
                name: "Test",
                artistItems: [NameIdPair(name: "Track Artist", id: "a1")]
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track?.artistName == "Track Artist")
        }

        @Test("Handles track with no mediaSources")
        func noMediaSources() {
            let dto = BaseItemDto(
                id: "track1",
                name: "Test"
            )
            let track = JellyfinMapper.mapTrack(dto)
            #expect(track != nil)
            #expect(track?.codec == nil)
            #expect(track?.bitRate == nil)
            #expect(track?.sampleRate == nil)
            #expect(track?.channelCount == nil)
        }
    }

    // MARK: - mapEpisode

    @Suite("mapEpisode")
    struct MapEpisodeTests {

        @Test("Maps series and season IDs")
        func basicMapping() {
            let dto = BaseItemDto(
                id: "ep1",
                name: "Pilot",
                overview: "First episode",
                runTimeTicks: 25_000_000_000,
                seriesId: "series1",
                seasonId: "season1",
                parentIndexNumber: 1,
                indexNumber: 1
            )
            let episode = JellyfinMapper.mapEpisode(dto)
            #expect(episode != nil)
            #expect(episode?.id == EpisodeID("ep1"))
            #expect(episode?.seriesId == SeriesID("series1"))
            #expect(episode?.seasonId == SeasonID("season1"))
            #expect(episode?.episodeNumber == 1)
            #expect(episode?.seasonNumber == 1)
            #expect(episode?.title == "Pilot")
            #expect(episode?.overview == "First episode")
            #expect(episode?.runtime == 2500.0)
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Pilot")
            #expect(JellyfinMapper.mapEpisode(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "ep1", name: nil)
            #expect(JellyfinMapper.mapEpisode(dto) == nil)
        }

        @Test("Handles nil seriesId and seasonId")
        func nilSeriesAndSeason() {
            let dto = BaseItemDto(id: "ep1", name: "Standalone")
            let episode = JellyfinMapper.mapEpisode(dto)
            #expect(episode != nil)
            #expect(episode?.seriesId == nil)
            #expect(episode?.seasonId == nil)
        }

        @Test("Handles nil runtime")
        func nilRuntime() {
            let dto = BaseItemDto(id: "ep1", name: "Test")
            let episode = JellyfinMapper.mapEpisode(dto)
            #expect(episode?.runtime == nil)
        }

        @Test("Maps userData when present")
        func withUserData() {
            let dto = BaseItemDto(
                id: "ep1",
                name: "Test",
                userData: BaseItemUserData(
                    isFavorite: false,
                    playbackPositionTicks: 300_000_000_000,
                    playCount: 1,
                    played: true
                )
            )
            let episode = JellyfinMapper.mapEpisode(dto)
            #expect(episode?.userData != nil)
            #expect(episode?.userData?.isPlayed == true)
            #expect(episode?.userData?.playbackPosition == 30000.0)
        }
    }

    // MARK: - mapSeason

    @Suite("mapSeason")
    struct MapSeasonTests {

        @Test("Maps basic fields")
        func basicMapping() {
            let dto = BaseItemDto(
                id: "season1",
                name: "Season 1",
                seriesId: "series1",
                indexNumber: 1,
                childCount: 10
            )
            let season = JellyfinMapper.mapSeason(dto)
            #expect(season != nil)
            #expect(season?.id == SeasonID("season1"))
            #expect(season?.seriesId == SeriesID("series1"))
            #expect(season?.seasonNumber == 1)
            #expect(season?.title == "Season 1")
            #expect(season?.episodeCount == 10)
        }

        @Test("Returns nil when seriesId is missing")
        func nilSeriesId() {
            let dto = BaseItemDto(id: "season1", name: "Season 1")
            #expect(JellyfinMapper.mapSeason(dto) == nil)
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Season 1", seriesId: "series1")
            #expect(JellyfinMapper.mapSeason(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "season1", name: nil, seriesId: "series1")
            #expect(JellyfinMapper.mapSeason(dto) == nil)
        }

        @Test("Defaults seasonNumber to 0 when indexNumber is nil")
        func defaultSeasonNumber() {
            let dto = BaseItemDto(
                id: "season1",
                name: "Specials",
                seriesId: "series1"
            )
            let season = JellyfinMapper.mapSeason(dto)
            #expect(season?.seasonNumber == 0)
        }

        @Test("Handles nil episodeCount")
        func nilEpisodeCount() {
            let dto = BaseItemDto(
                id: "season1",
                name: "Season 1",
                seriesId: "series1",
                indexNumber: 1
            )
            let season = JellyfinMapper.mapSeason(dto)
            #expect(season?.episodeCount == nil)
        }
    }

    // MARK: - mapPlaylist

    @Suite("mapPlaylist")
    struct MapPlaylistTests {

        @Test("Maps basic fields")
        func basicMapping() {
            let dto = BaseItemDto(
                id: "playlist1",
                name: "My Playlist",
                overview: "Best songs",
                runTimeTicks: 36_000_000_000,
                childCount: 15
            )
            let playlist = JellyfinMapper.mapPlaylist(dto)
            #expect(playlist != nil)
            #expect(playlist?.id == PlaylistID("playlist1"))
            #expect(playlist?.name == "My Playlist")
            #expect(playlist?.overview == "Best songs")
            #expect(playlist?.itemCount == 15)
            #expect(playlist?.duration == 3600.0)
        }

        @Test("Returns nil when id is missing")
        func nilId() {
            let dto = BaseItemDto(id: nil, name: "Test")
            #expect(JellyfinMapper.mapPlaylist(dto) == nil)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = BaseItemDto(id: "playlist1", name: nil)
            #expect(JellyfinMapper.mapPlaylist(dto) == nil)
        }

        @Test("Duration is nil when runTimeTicks is nil")
        func nilDuration() {
            let dto = BaseItemDto(id: "playlist1", name: "Test")
            let playlist = JellyfinMapper.mapPlaylist(dto)
            #expect(playlist?.duration == nil)
        }

        @Test("Maps dateAdded from dateCreated")
        func dateAdded() {
            let dto = BaseItemDto(
                id: "playlist1",
                name: "Test",
                dateCreated: "2023-06-15T10:30:00Z"
            )
            let playlist = JellyfinMapper.mapPlaylist(dto)
            #expect(playlist?.dateAdded != nil)
        }
    }

    // MARK: - mapUserData

    @Suite("mapUserData")
    struct MapUserDataTests {

        @Test("Converts playbackPositionTicks to seconds")
        func tickConversion() {
            let dto = BaseItemUserData(
                isFavorite: true,
                playbackPositionTicks: 50_000_000_000,
                playCount: 3,
                played: true
            )
            let userData = JellyfinMapper.mapUserData(dto)
            #expect(userData.isFavorite == true)
            #expect(userData.playbackPosition == 5000.0)
            #expect(userData.playCount == 3)
            #expect(userData.isPlayed == true)
        }

        @Test("Defaults nil values appropriately")
        func nilDefaults() {
            let dto = BaseItemUserData()
            let userData = JellyfinMapper.mapUserData(dto)
            #expect(userData.isFavorite == false)
            #expect(userData.playbackPosition == 0.0)
            #expect(userData.playCount == 0)
            #expect(userData.isPlayed == false)
            #expect(userData.lastPlayedDate == nil)
        }

        @Test("Maps lastPlayedDate when present")
        func lastPlayedDate() {
            let dto = BaseItemUserData(
                lastPlayedDate: "2023-06-15T10:30:00.000Z"
            )
            let userData = JellyfinMapper.mapUserData(dto)
            #expect(userData.lastPlayedDate != nil)
        }

        @Test("Position is zero when ticks are zero")
        func zeroTicks() {
            let dto = BaseItemUserData(playbackPositionTicks: 0)
            let userData = JellyfinMapper.mapUserData(dto)
            #expect(userData.playbackPosition == 0.0)
        }

        @Test("Handles large tick values")
        func largeTicks() {
            // 2 hours = 7200 seconds = 72_000_000_000 ticks
            let dto = BaseItemUserData(playbackPositionTicks: 72_000_000_000)
            let userData = JellyfinMapper.mapUserData(dto)
            #expect(userData.playbackPosition == 7200.0)
        }
    }

    // MARK: - parseDate

    @Suite("parseDate")
    struct ParseDateTests {

        @Test("Parses full precision with Z suffix (7 fractional digits)")
        func fullPrecisionZ() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00.0000000Z")
            #expect(date != nil)
        }

        @Test("Parses milliseconds with Z suffix")
        func millisecondsZ() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00.000Z")
            #expect(date != nil)
        }

        @Test("Parses seconds only with Z suffix")
        func secondsOnlyZ() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00Z")
            #expect(date != nil)
        }

        @Test("Parses full precision with timezone offset")
        func fullPrecisionTimezone() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00.0000000+00:00")
            #expect(date != nil)
        }

        @Test("Parses seconds with timezone offset")
        func secondsTimezone() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00+00:00")
            #expect(date != nil)
        }

        @Test("Returns nil for invalid date string")
        func invalidDate() {
            #expect(JellyfinMapper.parseDate("not a date") == nil)
            #expect(JellyfinMapper.parseDate("") == nil)
            #expect(JellyfinMapper.parseDate("2023-13-45") == nil)
        }

        @Test("Parsed dates have correct components")
        func dateComponents() {
            let date = JellyfinMapper.parseDate("2023-06-15T10:30:00.000Z")!
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(
                in: TimeZone(identifier: "UTC")!,
                from: date
            )
            #expect(components.year == 2023)
            #expect(components.month == 6)
            #expect(components.day == 15)
            #expect(components.hour == 10)
            #expect(components.minute == 30)
            #expect(components.second == 0)
        }
    }

    // MARK: - mapChapter

    @Suite("mapChapter")
    struct MapChapterTests {

        @Test("Converts ticks to seconds")
        func tickConversion() {
            let dto = ChapterInfoDto(
                startPositionTicks: 6_000_000_000,
                name: "Chapter 1",
                imagePath: nil,
                imageTag: "abc"
            )
            let chapter = JellyfinMapper.mapChapter(dto, index: 0)
            #expect(chapter != nil)
            #expect(chapter?.id == 0)
            #expect(chapter?.name == "Chapter 1")
            #expect(chapter?.startPosition == 600.0)
            #expect(chapter?.imageTag == "abc")
        }

        @Test("Uses provided index as chapter id")
        func indexAsId() {
            let dto = ChapterInfoDto(
                startPositionTicks: 0,
                name: "Intro",
                imagePath: nil,
                imageTag: nil
            )
            let chapter = JellyfinMapper.mapChapter(dto, index: 5)
            #expect(chapter?.id == 5)
        }

        @Test("Returns nil when name is missing")
        func nilName() {
            let dto = ChapterInfoDto(
                startPositionTicks: 0,
                name: nil,
                imagePath: nil,
                imageTag: nil
            )
            #expect(JellyfinMapper.mapChapter(dto, index: 0) == nil)
        }

        @Test("Returns nil when startPositionTicks is missing")
        func nilTicks() {
            let dto = ChapterInfoDto(
                startPositionTicks: nil,
                name: "Chapter",
                imagePath: nil,
                imageTag: nil
            )
            #expect(JellyfinMapper.mapChapter(dto, index: 0) == nil)
        }

        @Test("Handles zero ticks")
        func zeroTicks() {
            let dto = ChapterInfoDto(
                startPositionTicks: 0,
                name: "Start",
                imagePath: nil,
                imageTag: nil
            )
            let chapter = JellyfinMapper.mapChapter(dto, index: 0)
            #expect(chapter?.startPosition == 0.0)
        }
    }

    // MARK: - mapChapters

    @Suite("mapChapters")
    struct MapChaptersTests {

        @Test("Maps array of chapter DTOs")
        func mapsArray() {
            let dtos = [
                ChapterInfoDto(startPositionTicks: 0, name: "Intro", imagePath: nil, imageTag: nil),
                ChapterInfoDto(
                    startPositionTicks: 3_000_000_000, name: "Act 1", imagePath: nil,
                    imageTag: nil),
                ChapterInfoDto(
                    startPositionTicks: 6_000_000_000, name: "Act 2", imagePath: nil,
                    imageTag: nil),
            ]
            let chapters = JellyfinMapper.mapChapters(dtos)
            #expect(chapters.count == 3)
            #expect(chapters[0].id == 0)
            #expect(chapters[1].id == 1)
            #expect(chapters[2].id == 2)
            #expect(chapters[0].startPosition == 0.0)
            #expect(chapters[1].startPosition == 300.0)
            #expect(chapters[2].startPosition == 600.0)
        }

        @Test("Returns empty array for nil input")
        func nilInput() {
            let chapters = JellyfinMapper.mapChapters(nil)
            #expect(chapters.isEmpty)
        }

        @Test("Skips chapters with missing fields")
        func skipsInvalid() {
            let dtos = [
                ChapterInfoDto(startPositionTicks: 0, name: "Valid", imagePath: nil, imageTag: nil),
                ChapterInfoDto(
                    startPositionTicks: nil, name: "Missing ticks", imagePath: nil, imageTag: nil),
                ChapterInfoDto(startPositionTicks: 1000, name: nil, imagePath: nil, imageTag: nil),
            ]
            let chapters = JellyfinMapper.mapChapters(dtos)
            #expect(chapters.count == 1)
            #expect(chapters[0].name == "Valid")
        }
    }

    // MARK: - imageTypeString

    @Suite("imageTypeString")
    struct ImageTypeStringTests {

        @Test("Maps all image type cases to correct strings")
        func allCases() {
            #expect(JellyfinMapper.imageTypeString(.primary) == "Primary")
            #expect(JellyfinMapper.imageTypeString(.backdrop) == "Backdrop")
            #expect(JellyfinMapper.imageTypeString(.thumb) == "Thumb")
            #expect(JellyfinMapper.imageTypeString(.logo) == "Logo")
            #expect(JellyfinMapper.imageTypeString(.banner) == "Banner")
            #expect(JellyfinMapper.imageTypeString(.art) == "Art")
        }
    }

    // MARK: - sortByString

    @Suite("sortByString")
    struct SortByStringTests {

        @Test("Maps all sort field cases to correct strings")
        func allCases() {
            #expect(JellyfinMapper.sortByString(.name) == "SortName")
            #expect(JellyfinMapper.sortByString(.dateAdded) == "DateCreated")
            #expect(JellyfinMapper.sortByString(.dateCreated) == "DateCreated")
            #expect(JellyfinMapper.sortByString(.datePlayed) == "DatePlayed")
            #expect(JellyfinMapper.sortByString(.premiereDate) == "PremiereDate")
            #expect(JellyfinMapper.sortByString(.communityRating) == "CommunityRating")
            #expect(JellyfinMapper.sortByString(.criticRating) == "CriticRating")
            #expect(JellyfinMapper.sortByString(.runtime) == "Runtime")
            #expect(JellyfinMapper.sortByString(.random) == "Random")
            #expect(JellyfinMapper.sortByString(.albumArtist) == "AlbumArtist")
            #expect(JellyfinMapper.sortByString(.album) == "Album")
            #expect(JellyfinMapper.sortByString(.playCount) == "PlayCount")
        }
    }

    // MARK: - sortOrderString

    @Suite("sortOrderString")
    struct SortOrderStringTests {

        @Test("Maps sort order cases to correct strings")
        func allCases() {
            #expect(JellyfinMapper.sortOrderString(.ascending) == "Ascending")
            #expect(JellyfinMapper.sortOrderString(.descending) == "Descending")
        }
    }

    // MARK: - mapMediaStreams

    @Suite("mapMediaStreams")
    struct MapMediaStreamsTests {

        @Test("Maps video, audio, and subtitle streams")
        func basicMapping() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "Video", codec: "h264",
                    language: nil, title: nil, isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: "1080p H.264",
                    height: 1080, width: 1920, channels: nil,
                    bitRate: 8_000_000, sampleRate: nil,
                    videoRange: "SDR", videoRangeType: "SDR"
                ),
                MediaStreamInfo(
                    index: 1, type: "Audio", codec: "aac",
                    language: "eng", title: "English", isExternal: false,
                    isDefault: true, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: "English AAC",
                    height: nil, width: nil, channels: 6,
                    bitRate: 384_000, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                ),
                MediaStreamInfo(
                    index: 2, type: "Subtitle", codec: nil,
                    language: "eng", title: "English", isExternal: true,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: "English SRT",
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                ),
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams.count == 3)
            #expect(streams[0].type == .video)
            #expect(streams[0].codec == "h264")
            #expect(streams[0].width == 1920)
            #expect(streams[0].height == 1080)
            #expect(streams[1].type == .audio)
            #expect(streams[1].channels == 6)
            #expect(streams[2].type == .subtitle)
            #expect(streams[2].isExternal == true)
        }

        @Test("Skips streams with missing index")
        func missingIndex() {
            let dtos = [
                MediaStreamInfo(
                    index: nil, type: "Video", codec: "h264",
                    language: nil, title: nil, isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: nil,
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                )
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams.isEmpty)
        }

        @Test("Skips video/audio streams with missing codec")
        func missingCodec() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "Video", codec: nil,
                    language: nil, title: nil, isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: nil,
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                ),
                MediaStreamInfo(
                    index: 1, type: "Audio", codec: nil,
                    language: nil, title: nil, isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: nil,
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                ),
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams.isEmpty)
        }

        @Test("Allows subtitle streams without codec")
        func subtitleWithoutCodec() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "Subtitle", codec: nil,
                    language: "eng", title: nil, isExternal: false,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: "English",
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                )
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams.count == 1)
            #expect(streams[0].type == .subtitle)
        }

        @Test("Skips streams with unknown type")
        func unknownType() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "EmbeddedImage", codec: "png",
                    language: nil, title: nil, isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: nil,
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                )
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams.isEmpty)
        }

        @Test("Uses displayTitle over title when both present")
        func displayTitlePreference() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "Audio", codec: "aac",
                    language: nil, title: "Internal Title", isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: "Display Title",
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                )
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams[0].title == "Display Title")
        }

        @Test("Falls back to title when displayTitle is nil")
        func titleFallback() {
            let dtos = [
                MediaStreamInfo(
                    index: 0, type: "Audio", codec: "aac",
                    language: nil, title: "Internal Title", isExternal: nil,
                    isDefault: nil, isForced: nil, deliveryMethod: nil,
                    deliveryUrl: nil, displayTitle: nil,
                    height: nil, width: nil, channels: nil,
                    bitRate: nil, sampleRate: nil,
                    videoRange: nil, videoRangeType: nil
                )
            ]
            let streams = JellyfinMapper.mapMediaStreams(dtos)
            #expect(streams[0].title == "Internal Title")
        }
    }

    // MARK: - mapMediaSegment

    @Suite("mapMediaSegment")
    struct MapMediaSegmentTests {

        @Test("Maps segment with known type")
        func knownType() {
            let dto = MediaSegmentDto(
                id: "seg1",
                itemId: "item1",
                type: "Intro",
                startTicks: 0,
                endTicks: 900_000_000
            )
            let segment = JellyfinMapper.mapMediaSegment(dto)
            #expect(segment != nil)
            #expect(segment?.id == "seg1")
            #expect(segment?.itemId == ItemID("item1"))
            #expect(segment?.type == .intro)
            #expect(segment?.startTime == 0.0)
            #expect(segment?.endTime == 90.0)
        }

        @Test("Returns nil when required fields are missing")
        func missingFields() {
            #expect(
                JellyfinMapper.mapMediaSegment(
                    MediaSegmentDto(
                        id: nil, itemId: "item1", type: "Intro",
                        startTicks: 0, endTicks: 100)
                ) == nil)
            #expect(
                JellyfinMapper.mapMediaSegment(
                    MediaSegmentDto(
                        id: "seg1", itemId: nil, type: "Intro",
                        startTicks: 0, endTicks: 100)
                ) == nil)
            #expect(
                JellyfinMapper.mapMediaSegment(
                    MediaSegmentDto(
                        id: "seg1", itemId: "item1", type: nil,
                        startTicks: 0, endTicks: 100)
                ) == nil)
            #expect(
                JellyfinMapper.mapMediaSegment(
                    MediaSegmentDto(
                        id: "seg1", itemId: "item1", type: "Intro",
                        startTicks: nil, endTicks: 100)
                ) == nil)
            #expect(
                JellyfinMapper.mapMediaSegment(
                    MediaSegmentDto(
                        id: "seg1", itemId: "item1", type: "Intro",
                        startTicks: 0, endTicks: nil)
                ) == nil)
        }

        @Test("Unknown segment type maps to .unknown")
        func unknownType() {
            let dto = MediaSegmentDto(
                id: "seg1",
                itemId: "item1",
                type: "SomeFutureType",
                startTicks: 0,
                endTicks: 100
            )
            let segment = JellyfinMapper.mapMediaSegment(dto)
            #expect(segment?.type == .unknown)
        }
    }
}
