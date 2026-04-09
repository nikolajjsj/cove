import Foundation
import JellyfinAPI
import MediaServerKit
import Models
import Networking
import os

/// Jellyfin implementation of all MediaServerKit protocols.
/// This is the only module that knows about Jellyfin specifics.
public final class JellyfinServerProvider: MediaServerProvider,
    MusicProvider, VideoProvider, TranscodingProvider,
    PlaybackReportingProvider, DownloadableProvider
{
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "JellyfinProvider")
    private let keychain: KeychainService
    private let state: ProviderState

    public init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
        self.state = ProviderState()
    }

    // MARK: - Private Helpers

    /// Returns the authenticated client and user ID, or throws if not connected.
    private func authenticatedClient() throws -> (JellyfinAPIClient, String) {
        guard let client = state.client, let userId = client.userId ?? state.connection?.userId
        else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        return (client, userId)
    }

    /// Returns the authenticated client, or throws if not connected.
    private func client() throws -> JellyfinAPIClient {
        guard let client = state.client else {
            throw AppError.authFailed(reason: "Not connected to a server")
        }
        return client
    }

    // MARK: - Connection

    public func connect(url: URL, credentials: Credentials) async throws -> ServerConnection {
        logger.info("Connecting to Jellyfin server at \(url.absoluteString)")

        let client = JellyfinAPIClient(baseURL: url)

        // Step 1: Discover server info
        let serverInfo = try await client.getPublicSystemInfo()
        let serverName = serverInfo.serverName ?? url.host ?? "Jellyfin Server"
        logger.info("Discovered server: \(serverName) (v\(serverInfo.version ?? "unknown"))")

        // Step 2: Authenticate
        let authResult = try await client.authenticateByName(
            username: credentials.username,
            password: credentials.password
        )

        guard let token = authResult.accessToken else {
            throw AppError.authFailed(reason: "Server did not return an access token")
        }

        guard let userId = authResult.user?.id else {
            throw AppError.authFailed(reason: "Server did not return a user ID")
        }

        // Step 3: Build the connection
        let connection = ServerConnection(
            name: serverName,
            url: url,
            userId: userId,
            serverType: .jellyfin
        )

        // Step 4: Persist token to Keychain
        try keychain.setToken(token, forServerID: connection.id.uuidString)
        logger.info("Token stored in Keychain for server \(connection.id.uuidString)")

        // Step 5: Store client for subsequent requests
        client.setAccessToken(token)
        client.setUserId(userId)
        state.set(client: client, connection: connection)

        logger.info("Successfully connected to \(serverName) as user \(userId)")
        return connection
    }

    public func disconnect() async {
        if let connection = state.connection {
            keychain.deleteToken(forServerID: connection.id.uuidString)
            logger.info("Disconnected from \(connection.name)")
        }
        state.clear()
    }

    /// Restore a previous connection using a persisted token.
    /// Call this on app launch with a stored `ServerConnection`.
    public func restore(connection: ServerConnection) -> Bool {
        guard let token = keychain.token(forServerID: connection.id.uuidString) else {
            logger.warning("No token found for server \(connection.id.uuidString)")
            return false
        }
        let client = JellyfinAPIClient(baseURL: connection.url)
        client.setAccessToken(token)
        client.setUserId(connection.userId)
        state.set(client: client, connection: connection)
        logger.info("Restored connection to \(connection.name)")
        return true
    }

    // MARK: - Library Browsing

    public func libraries() async throws -> [MediaLibrary] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getUserViews(userId: userId)
        let items = result.items ?? []
        return items.compactMap { dto -> MediaLibrary? in
            guard let id = dto.id, let name = dto.name else { return nil }
            let collectionType = dto.collectionType.flatMap { CollectionType(rawValue: $0) }
            return MediaLibrary(id: ItemID(id), name: name, collectionType: collectionType)
        }
    }

    public func items(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions)
        async throws -> [MediaItem]
    {
        let result = try await pagedItems(in: library, sort: sort, filter: filter)
        return result.items
    }

    public func pagedItems(in library: MediaLibrary, sort: SortOptions, filter: FilterOptions)
        async throws -> PagedResult<MediaItem>
    {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            parentId: library.id.rawValue,
            includeItemTypes: filter.includeItemTypes,
            sortBy: JellyfinMapper.sortByString(sort.field),
            sortOrder: JellyfinMapper.sortOrderString(sort.order),
            limit: filter.limit,
            startIndex: filter.startIndex,
            searchTerm: filter.searchTerm,
            isFavorite: filter.isFavorite,
            isPlayed: filter.isPlayed,
            genres: filter.genres
        )
        let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
        return PagedResult(
            items: items,
            startIndex: filter.startIndex ?? 0,
            totalCount: result.totalRecordCount ?? items.count
        )
    }

    public func item(id: ItemID) async throws -> MediaItem {
        let (client, userId) = try authenticatedClient()
        let dto = try await client.getItem(userId: userId, itemId: id.rawValue)
        guard let item = JellyfinMapper.mapItem(dto, baseURL: client.baseURL) else {
            throw AppError.itemNotFound(id: id)
        }
        return item
    }

    public func similarItems(for item: MediaItem, limit: Int? = nil) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getSimilarItems(
            itemId: item.id.rawValue,
            userId: userId,
            limit: limit
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func suggestedItems(limit: Int = 8) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        do {
            // Try the Suggestions endpoint (Jellyfin 10.7+)
            let result = try await client.getSuggestions(userId: userId, limit: limit)
            let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
            if !items.isEmpty { return items }
        } catch {
            // Suggestions endpoint not available — fall through to fallback
        }
        // Fallback: random unplayed movies and series
        let result = try await client.getItems(
            userId: userId,
            includeItemTypes: ["Movie", "Series"],
            sortBy: "Random",
            limit: limit,
            isPlayed: false
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func personItems(personId: ItemID) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            sortBy: "ProductionYear,SortName",
            sortOrder: "Descending",
            fields: [
                "Overview", "Genres", "UserData", "CommunityRating", "OfficialRating",
                "ProductionYear",
            ],
            personIds: [personId.rawValue]
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL? {
        guard let client = state.client else { return nil }

        // If the item carries image-tag metadata, check whether this type exists.
        // When imageTags is nil (older code paths / placeholder items), fall through
        // and construct the URL optimistically.
        let tag: String?
        if let tags = item.imageTags {
            guard let t = tags[type] else { return nil }
            tag = t
        } else {
            tag = nil
        }

        let maxWidth = maxSize.map { Int($0.width) }
        let maxHeight = maxSize.map { Int($0.height) }
        return client.imageURL(
            itemId: item.id.rawValue,
            imageType: JellyfinMapper.imageTypeString(type),
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            tag: tag
        )
    }

    /// Build a URL for a chapter image.
    public func chapterImageURL(
        itemId: ItemID,
        chapterIndex: Int,
        tag: String,
        maxWidth: Int = 400
    ) -> URL? {
        guard let client = state.client else { return nil }
        return client.chapterImageURL(
            itemId: itemId.rawValue,
            chapterIndex: chapterIndex,
            tag: tag,
            maxWidth: maxWidth
        )
    }

    public func search(query: String, mediaTypes: [MediaType]) async throws -> SearchResults {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            searchTerm: query
        )
        let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
        return SearchResults(items: items)
    }

    public func searchPaged(
        query: String, includeItemTypes: [String]?, limit: Int?, startIndex: Int?
    ) async throws -> PagedResult<MediaItem> {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            includeItemTypes: includeItemTypes,
            limit: limit,
            startIndex: startIndex,
            searchTerm: query
        )
        let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
        return PagedResult(
            items: items,
            startIndex: startIndex ?? 0,
            totalCount: result.totalRecordCount ?? items.count
        )
    }

    // MARK: - MusicProvider (Phase 4)

    public func albums(artist: ArtistID) async throws -> [Album] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            parentId: artist.rawValue,
            includeItemTypes: ["MusicAlbum"],
            sortBy: "ProductionYear,SortName",
            sortOrder: "Descending"
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapAlbum($0) }
    }

    public func tracks(album: AlbumID) async throws -> [Track] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            parentId: album.rawValue,
            includeItemTypes: ["Audio"],
            sortBy: "SortName",
            sortOrder: "Ascending"
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapTrack($0) }
    }

    public func playlists() async throws -> [Playlist] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            includeItemTypes: ["Playlist"],
            sortBy: "SortName"
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapPlaylist($0) }
    }

    public func lyrics(track: TrackID) async throws -> Lyrics? {
        let (client, _) = try authenticatedClient()
        let response = try await client.getLyrics(itemId: track.rawValue)
        guard let lyricDtos = response.lyrics, !lyricDtos.isEmpty else { return nil }
        let lines = lyricDtos.compactMap { dto -> LyricLine? in
            guard let text = dto.text else { return nil }
            // Start time from Jellyfin is in ticks (10,000,000 ticks per second)
            let startTime: TimeInterval? = dto.start.map { JellyfinTicks.toSeconds($0) }
            return LyricLine(startTime: startTime, text: text)
        }
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines)
    }

    public func playlistTracks(playlist: PlaylistID) async throws -> [Track] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getPlaylistItems(
            playlistId: playlist.rawValue,
            userId: userId
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapTrack($0) }
    }

    public func createPlaylist(name: String, trackIds: [ItemID]) async throws -> Playlist? {
        let (client, userId) = try authenticatedClient()
        let response = try await client.createPlaylist(
            userId: userId,
            name: name,
            trackIds: trackIds.map(\.rawValue)
        )
        guard let id = response.id else { return nil }
        // Fetch the created playlist to get full metadata
        let item = try await client.getItem(userId: userId, itemId: id)
        return JellyfinMapper.mapPlaylist(item)
    }

    public func addToPlaylist(playlist: PlaylistID, trackIds: [ItemID]) async throws {
        let (client, _) = try authenticatedClient()
        try await client.addToPlaylist(
            playlistId: playlist.rawValue,
            trackIds: trackIds.map(\.rawValue)
        )
    }

    public func removeFromPlaylist(playlist: PlaylistID, entryIds: [String]) async throws {
        let (client, _) = try authenticatedClient()
        try await client.removeFromPlaylist(
            playlistId: playlist.rawValue,
            entryIds: entryIds
        )
    }

    public func renamePlaylist(playlist: PlaylistID, name: String) async throws {
        let (client, _) = try authenticatedClient()
        try await client.updateItem(itemId: playlist.rawValue, name: name)
    }

    public func deletePlaylist(playlist: PlaylistID) async throws {
        let (client, _) = try authenticatedClient()
        try await client.deleteItem(itemId: playlist.rawValue)
    }

    public func setFavorite(itemId: ItemID, isFavorite: Bool) async throws {
        let (client, userId) = try authenticatedClient()
        if isFavorite {
            try await client.addFavorite(userId: userId, itemId: itemId.rawValue)
        } else {
            try await client.removeFavorite(userId: userId, itemId: itemId.rawValue)
        }
    }

    public func setPlayed(itemId: ItemID, isPlayed: Bool) async throws {
        let (client, userId) = try authenticatedClient()
        if isPlayed {
            try await client.markPlayed(userId: userId, itemId: itemId.rawValue)
        } else {
            try await client.markUnplayed(userId: userId, itemId: itemId.rawValue)
        }
    }

    public func instantMix(for itemId: ItemID, limit: Int = 50) async throws -> [Track] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getInstantMix(
            itemId: itemId.rawValue,
            userId: userId,
            limit: limit
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapTrack($0) }
    }

    // MARK: - Audio Streaming

    /// Build a universal audio stream URL for a track.
    public func audioStreamURL(for track: Track) -> URL? {
        guard let client = state.client else { return nil }
        return client.audioStreamURL(itemId: track.id.rawValue)
    }

    // MARK: - VideoProvider (Phase 5)

    public func seasons(series: SeriesID) async throws -> [Season] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getSeasons(seriesId: series.rawValue, userId: userId)
        return (result.items ?? []).compactMap { JellyfinMapper.mapSeason($0) }
    }

    public func episodes(season: SeasonID) async throws -> [Episode] {
        let (client, userId) = try authenticatedClient()
        // Use getItems with parentId = season to get episodes
        let result = try await client.getItems(
            userId: userId,
            parentId: season.rawValue,
            includeItemTypes: ["Episode"],
            sortBy: "IndexNumber",
            sortOrder: "Ascending",
            fields: ["Overview", "UserData", "DateCreated", "MediaSources"]
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapEpisode($0) }
    }

    public func specialFeatures(for item: MediaItem) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let dtos = try await client.getSpecialFeatures(
            itemId: item.id.rawValue,
            userId: userId
        )
        return dtos.compactMap { JellyfinMapper.mapItem($0) }
    }

    public func localTrailers(for item: MediaItem) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let dtos = try await client.getLocalTrailers(
            itemId: item.id.rawValue,
            userId: userId
        )
        return dtos.compactMap { JellyfinMapper.mapItem($0) }
    }

    /// Fetch skippable segments (intro, credits, recap, etc.) for an item.
    ///
    /// Tries multiple sources in order:
    /// 1. Native Jellyfin 10.9+ MediaSegments API
    /// 2. Intro Skipper plugin (`/Episode/{id}/IntroSkipperSegments`)
    /// 3. Older Intro Skipper plugin (`/Episode/{id}/IntroTimestamps`)
    public func mediaSegments(for itemId: ItemID) async throws -> [MediaSegment] {
        let (client, _) = try authenticatedClient()

        // 1. Try native MediaSegments API (Jellyfin 10.9+)
        //    Use only valid Jellyfin MediaSegmentType values (no "Credits" — it's "Outro")
        do {
            let result = try await client.getMediaSegments(
                itemId: itemId.rawValue,
                includeSegmentTypes: ["Intro", "Outro", "Recap", "Commercial", "Preview"]
            )
            let segments = JellyfinMapper.mapMediaSegments(result)
            logger.info("Native MediaSegments for \(itemId.rawValue): \(segments.count) segment(s)")
            if !segments.isEmpty {
                return segments
            }
        } catch {
            logger.warning(
                "Native MediaSegments API failed for \(itemId.rawValue): \(error.localizedDescription)"
            )
        }

        // 2. Try Intro Skipper plugin (newer endpoint: /Episode/{id}/IntroSkipperSegments)
        do {
            let skipperSegments = try await client.getIntroSkipperSegments(itemId: itemId.rawValue)
            logger.info(
                "IntroSkipperSegments raw response for \(itemId.rawValue): \(skipperSegments.count) key(s): \(skipperSegments.keys.sorted().joined(separator: ", "))"
            )
            for (key, seg) in skipperSegments {
                logger.info(
                    "  [\(key)] valid=\(seg.valid?.description ?? "nil") start=\(seg.start?.description ?? "nil") end=\(seg.end?.description ?? "nil")"
                )
            }
            let segments = JellyfinMapper.mapIntroSkipperSegments(skipperSegments, itemId: itemId)
            logger.info(
                "IntroSkipperSegments for \(itemId.rawValue): \(segments.count) mapped segment(s)")
            if !segments.isEmpty {
                return segments
            }
        } catch {
            logger.warning(
                "IntroSkipperSegments API failed for \(itemId.rawValue): \(error.localizedDescription)"
            )
        }

        // 3. Try older Intro Skipper plugin endpoint (/Episode/{id}/IntroTimestamps)
        do {
            let timestamp = try await client.getIntroTimestamps(itemId: itemId.rawValue)
            if timestamp.valid == true,
                let start = timestamp.start,
                let end = timestamp.end,
                end > start
            {
                let segment = MediaSegment(
                    id: "\(itemId.rawValue)-intro",
                    itemId: itemId,
                    type: .intro,
                    startTime: start,
                    endTime: end
                )
                logger.info("IntroTimestamps for \(itemId.rawValue): found intro segment")
                return [segment]
            }
        } catch {
            logger.warning(
                "IntroTimestamps API failed for \(itemId.rawValue): \(error.localizedDescription)")
        }

        logger.info("No media segments found for \(itemId.rawValue) from any source")
        return []
    }

    public func resumeItems() async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getResumeItems(
            userId: userId, mediaTypes: ["Video"], limit: 12)
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func streamURL(for item: MediaItem, profile: DeviceProfile?) async throws -> StreamInfo {
        let (client, userId) = try authenticatedClient()
        let resolvedProfile = profile ?? deviceProfile()

        let playbackInfo = try await client.getPlaybackInfo(
            userId: userId, itemId: item.id.rawValue, profile: resolvedProfile)

        guard let source = playbackInfo.mediaSources?.first else {
            throw AppError.playbackFailed(reason: "No media source available")
        }

        let mediaStreams = JellyfinMapper.mapMediaStreams(source.mediaStreams ?? [])
        let sourceId = source.id ?? item.id.rawValue

        // Extract codec info from media streams for logging/debugging
        let videoCodec = source.mediaStreams?
            .first(where: { $0.type == "Video" })?.codec?.lowercased()
        let audioCodec = source.mediaStreams?
            .first(where: { $0.type == "Audio" })?.codec?.lowercased()
        let container = source.container?.lowercased()

        // Log raw server response for diagnostics
        logger.info(
            "PlaybackInfo response: container=\(container ?? "nil") video=\(videoCodec ?? "nil") audio=\(audioCodec ?? "nil") directPlay=\(source.supportsDirectPlay ?? false) directStream=\(source.supportsDirectStream ?? false) transcodingUrl=\(source.transcodingUrl != nil ? "present" : "nil")"
        )

        // Client-side safety net: verify that AVPlayer can actually handle the format
        // before trusting the server's DirectPlay/DirectStream decision.
        let avPlayerCompatible = Self.isAVPlayerCompatible(
            container: container, videoCodec: videoCodec, audioCodec: audioCodec
        )

        // Branch 1: Direct Play — file is natively supported as-is
        if source.supportsDirectPlay == true && avPlayerCompatible,
            let url = client.videoStreamURL(
                itemId: item.id.rawValue,
                mediaSourceId: sourceId,
                container: source.container,
                staticStream: true
            )
        {
            logger.info("Stream resolved: DirectPlay")
            return StreamInfo(
                url: url,
                playMethod: .directPlay,
                container: container,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                mediaStreams: mediaStreams,
                mediaSourceId: sourceId
            )
        }

        // Branch 2: Direct Stream — server remuxes container, no re-encoding
        // Only safe if the codecs themselves are AVPlayer-compatible (container mismatch is fine
        // since the server will remux into a compatible container).
        let codecsCompatible = Self.areCodecsAVPlayerCompatible(
            videoCodec: videoCodec, audioCodec: audioCodec
        )

        if source.supportsDirectStream == true && codecsCompatible,
            let url = client.videoStreamURL(
                itemId: item.id.rawValue,
                mediaSourceId: sourceId,
                staticStream: false
            )
        {
            logger.info("Stream resolved: DirectStream")
            return StreamInfo(
                url: url,
                playMethod: .directStream,
                container: container,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                mediaStreams: mediaStreams,
                mediaSourceId: sourceId
            )
        }

        // If server said DirectPlay/DirectStream but we rejected it, log why
        if source.supportsDirectPlay == true && !avPlayerCompatible {
            logger.warning(
                "Server suggested DirectPlay but format is not AVPlayer-compatible — falling through to transcode"
            )
        }
        if source.supportsDirectStream == true && !codecsCompatible {
            logger.warning(
                "Server suggested DirectStream but codecs are not AVPlayer-compatible — falling through to transcode"
            )
        }

        // Branch 3: Transcode — server re-encodes via HLS
        if let transcodingPath = source.transcodingUrl,
            let url = client.hlsStreamURL(transcodingPath: transcodingPath)
        {
            logger.info("Stream resolved: Transcode")
            return StreamInfo(
                url: url,
                playMethod: .transcode,
                container: container,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                mediaStreams: mediaStreams,
                mediaSourceId: sourceId
            )
        }

        // Branch 4: Server suggested DirectPlay/DirectStream for a format AVPlayer can't handle
        // and didn't provide a transcodingUrl. Re-request with direct play/stream disabled
        // to force the server to give us a transcode URL.
        if !avPlayerCompatible || !codecsCompatible {
            logger.warning(
                "No transcode URL in initial response — retrying with forced transcoding"
            )

            let retryPlaybackInfo = try await client.getPlaybackInfoTranscodeOnly(
                userId: userId, itemId: item.id.rawValue, profile: resolvedProfile)

            if let retrySource = retryPlaybackInfo.mediaSources?.first,
                let transcodingPath = retrySource.transcodingUrl,
                let url = client.hlsStreamURL(transcodingPath: transcodingPath)
            {
                logger.info("Stream resolved: Transcode (forced retry)")
                return StreamInfo(
                    url: url,
                    playMethod: .transcode,
                    container: container,
                    videoCodec: videoCodec,
                    audioCodec: audioCodec,
                    mediaStreams: mediaStreams,
                    mediaSourceId: sourceId
                )
            }
        }

        throw AppError.playbackFailed(reason: "Unable to resolve a playable stream URL")
    }

    // MARK: - AVPlayer Compatibility Check

    /// Containers and codecs that AVPlayer can reliably handle on iOS 18+ / macOS 15+.
    private static let avPlayerContainers: Set<String> = ["mp4", "m4v", "mov"]
    private static let avPlayerVideoCodecs: Set<String> = ["h264", "hevc", "h265"]
    private static let avPlayerAudioCodecs: Set<String> = [
        "aac", "mp3", "alac", "flac", "ac3", "eac3",
    ]

    /// Full check: container + video codec + audio codec must all be AVPlayer-compatible.
    private static func isAVPlayerCompatible(
        container: String?, videoCodec: String?, audioCodec: String?
    ) -> Bool {
        guard let container, avPlayerContainers.contains(container) else { return false }
        return areCodecsAVPlayerCompatible(videoCodec: videoCodec, audioCodec: audioCodec)
    }

    /// Codec-only check: used for DirectStream where the server remuxes the container.
    private static func areCodecsAVPlayerCompatible(
        videoCodec: String?, audioCodec: String?
    ) -> Bool {
        guard let videoCodec, avPlayerVideoCodecs.contains(videoCodec) else { return false }
        // Audio codec is optional — some streams are video-only
        if let audioCodec, !avPlayerAudioCodecs.contains(audioCodec) { return false }
        return true
    }

    // MARK: - TranscodingProvider (Phase 5)

    public func deviceProfile() -> DeviceProfile {
        .appleDevice()
    }

    public func transcodedStreamURL(for item: MediaItem, profile: DeviceProfile) async throws -> URL
    {
        let (client, userId) = try authenticatedClient()
        let playbackInfo = try await client.getPlaybackInfo(
            userId: userId, itemId: item.id.rawValue, profile: profile)
        guard let source = playbackInfo.mediaSources?.first,
            let transcodingPath = source.transcodingUrl,
            let url = client.hlsStreamURL(transcodingPath: transcodingPath)
        else {
            throw AppError.playbackFailed(reason: "Server could not provide a transcode URL")
        }
        return url
    }

    // MARK: - Shows & Continue Watching (Phase 5)

    // MARK: - Collections (Boxsets)

    /// Fetch the items (typically movies) inside a collection / boxset.
    public func collectionItems(collectionId: ItemID) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getItems(
            userId: userId,
            parentId: collectionId.rawValue,
            sortBy: "SortName",
            sortOrder: "Ascending",
            recursive: false
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    /// Get episodes for a specific series and season.
    public func episodes(series: SeriesID, season: SeasonID) async throws -> [Episode] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getEpisodes(
            seriesId: series.rawValue,
            seasonId: season.rawValue,
            userId: userId
        )
        return (result.items ?? []).compactMap { JellyfinMapper.mapEpisode($0) }
    }

    /// Get "next up" episodes across all series or for a specific series.
    public func nextUp(seriesId: SeriesID? = nil) async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getNextUp(userId: userId, seriesId: seriesId?.rawValue)
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    /// Find the next episode after the given item by querying the series episode list.
    ///
    /// Unlike `nextUp(seriesId:)` which relies on server-side watch history,
    /// this method uses the `StartItemId` parameter to get episodes starting
    /// from the current one, then returns the episode immediately after it.
    /// This reliably finds the next episode regardless of watch state.
    public func nextEpisodeAfter(item: MediaItem) async throws -> MediaItem? {
        guard item.mediaType == .episode, let seriesId = item.seriesId else { return nil }
        let (client, userId) = try authenticatedClient()
        // Fetch 2 episodes starting from the current one (current + next)
        let result = try await client.getEpisodes(
            seriesId: seriesId.rawValue,
            startItemId: item.id.rawValue,
            limit: 2,
            userId: userId
        )
        let items = (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
        // The first item is the current episode; return the second if it exists
        return items.first { $0.id != item.id }
    }

    /// Build a subtitle URL for a video item.
    public func subtitleURL(
        itemId: ItemID, mediaSourceId: String, subtitleIndex: Int, format: String = "vtt"
    ) -> URL? {
        guard let client = state.client else { return nil }
        return client.subtitleURL(
            itemId: itemId.rawValue,
            mediaSourceId: mediaSourceId,
            subtitleIndex: subtitleIndex,
            format: format
        )
    }

    // MARK: - PlaybackReportingProvider (Phase 4/5)

    public func reportPlaybackStart(item: MediaItem, position: TimeInterval) async throws {
        let client = try client()
        let positionTicks = JellyfinTicks.fromSeconds(position)
        try await client.reportPlaybackStart(
            itemId: item.id.rawValue,
            positionTicks: positionTicks
        )
    }

    public func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws {
        let client = try client()
        let positionTicks = JellyfinTicks.fromSeconds(position)
        try await client.reportPlaybackProgress(
            itemId: item.id.rawValue,
            positionTicks: positionTicks,
            isPaused: false
        )
    }

    public func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws {
        let client = try client()
        let positionTicks = JellyfinTicks.fromSeconds(position)
        try await client.reportPlaybackStopped(
            itemId: item.id.rawValue,
            positionTicks: positionTicks
        )
    }

    // MARK: - DownloadableProvider (Phase 6)

    public func downloadInfo(for item: MediaItem, profile: DeviceProfile?) async throws
        -> DownloadInfo
    {
        let (client, userId) = try authenticatedClient()
        let resolvedProfile = profile ?? deviceProfile()

        // Query PlaybackInfo to determine if the file needs remuxing/transcoding
        let playbackInfo = try await client.getPlaybackInfo(
            userId: userId, itemId: item.id.rawValue, profile: resolvedProfile)

        guard let source = playbackInfo.mediaSources?.first else {
            throw AppError.downloadFailed(
                itemTitle: item.title,
                reason: "No media source available"
            )
        }

        let sourceId = source.id ?? item.id.rawValue

        // If the file is directly playable, download the raw original
        if source.supportsDirectPlay == true {
            guard let url = client.downloadURL(itemId: item.id.rawValue) else {
                throw AppError.downloadFailed(
                    itemTitle: item.title,
                    reason: "Unable to build download URL"
                )
            }
            return DownloadInfo(url: url, expectedBytes: source.size)
        }

        // Otherwise, request a compatible format via the stream endpoint
        guard
            let url = client.compatibleDownloadURL(
                itemId: item.id.rawValue,
                mediaSourceId: sourceId
            )
        else {
            throw AppError.downloadFailed(
                itemTitle: item.title,
                reason: "Unable to build compatible download URL"
            )
        }
        return DownloadInfo(url: url, expectedBytes: source.size)
    }
}

// MARK: - Internal Helpers

/// Thread-safe mutable state for the provider.
private final class ProviderState: @unchecked Sendable {
    private struct State {
        var client: JellyfinAPIClient?
        var connection: ServerConnection?
    }

    private let storage = OSAllocatedUnfairLock(initialState: State())

    var client: JellyfinAPIClient? {
        storage.withLock { $0.client }
    }

    var connection: ServerConnection? {
        storage.withLock { $0.connection }
    }

    func set(client: JellyfinAPIClient, connection: ServerConnection) {
        storage.withLock { state in
            state.client = client
            state.connection = connection
        }
    }

    func clear() {
        storage.withLock { state in
            state.client = nil
            state.connection = nil
        }
    }
}

/// Placeholder error for not-yet-implemented methods.
private struct NotImplementedError: Error, CustomStringConvertible {
    var description: String { "This feature is not yet implemented" }
}
