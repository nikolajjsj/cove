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
        state.set(client: client, connection: connection)
        logger.info("Restored connection to \(connection.name)")
        return true
    }

    // MARK: - Library Browsing

    public func libraries() async throws -> [MediaLibrary] {
        let client = try client()
        let folders = try await client.getVirtualFolders()
        return folders.compactMap { JellyfinMapper.mapLibrary($0) }
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
            isFavorite: filter.isFavorite
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
        guard let item = JellyfinMapper.mapItem(dto) else {
            throw AppError.itemNotFound(id: id)
        }
        return item
    }

    public func imageURL(for item: MediaItem, type: ImageType, maxSize: CGSize?) -> URL? {
        guard let client = state.client else { return nil }
        let maxWidth = maxSize.map { Int($0.width) }
        let maxHeight = maxSize.map { Int($0.height) }
        return client.imageURL(
            itemId: item.id.rawValue,
            imageType: JellyfinMapper.imageTypeString(type),
            maxWidth: maxWidth,
            maxHeight: maxHeight
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
        // Lyrics endpoint is complex; returning nil for now.
        return nil
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

    public func resumeItems() async throws -> [MediaItem] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getResumeItems(
            userId: userId, mediaTypes: ["Video"], limit: 12)
        return (result.items ?? []).compactMap { JellyfinMapper.mapItem($0) }
    }

    public func streamURL(for item: MediaItem, profile: DeviceProfile?) async throws -> StreamInfo {
        let (client, userId) = try authenticatedClient()

        let playbackInfo = try await client.getPlaybackInfo(
            userId: userId, itemId: item.id.rawValue)

        guard let source = playbackInfo.mediaSources?.first else {
            throw AppError.playbackFailed(reason: "No media source available")
        }

        let mediaStreams = JellyfinMapper.mapMediaStreams(source.mediaStreams ?? [])
        let sourceId = source.id ?? item.id.rawValue

        // Decide: direct play vs transcode
        if source.supportsDirectPlay == true || source.supportsDirectStream == true,
            let url = client.videoStreamURL(
                itemId: item.id.rawValue, mediaSourceId: sourceId, container: source.container)
        {
            return StreamInfo(
                url: url,
                isTranscoded: false,
                mediaStreams: mediaStreams,
                directPlaySupported: true
            )
        }

        // Try transcode
        if let transcodingPath = source.transcodingUrl,
            let url = client.hlsStreamURL(transcodingPath: transcodingPath)
        {
            return StreamInfo(
                url: url,
                isTranscoded: true,
                mediaStreams: mediaStreams,
                directPlaySupported: false
            )
        }

        throw AppError.playbackFailed(reason: "Unable to resolve a playable stream URL")
    }

    // MARK: - TranscodingProvider (Phase 5)

    public func deviceProfile() -> DeviceProfile {
        DeviceProfile(
            name: "Cove iOS",
            maxStreamingBitrate: 120_000_000,
            supportedVideoCodecs: ["h264", "hevc", "h265"],
            supportedAudioCodecs: ["aac", "mp3", "alac", "flac", "opus"],
            supportedContainers: ["mp4", "mov", "m4v", "hls", "ts", "mkv"],
            supportsDirectPlay: true,
            supportsDirectStream: true,
            supportsTranscoding: true
        )
    }

    public func transcodedStreamURL(for item: MediaItem, profile: DeviceProfile) async throws -> URL
    {
        let (client, userId) = try authenticatedClient()
        let playbackInfo = try await client.getPlaybackInfo(
            userId: userId, itemId: item.id.rawValue)
        guard let source = playbackInfo.mediaSources?.first,
            let transcodingPath = source.transcodingUrl,
            let url = client.hlsStreamURL(transcodingPath: transcodingPath)
        else {
            throw AppError.playbackFailed(reason: "Server could not provide a transcode URL")
        }
        return url
    }

    // MARK: - Shows & Continue Watching (Phase 5)

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
        let positionTicks = Int64(position * 10_000_000)
        try await client.reportPlaybackStart(
            itemId: item.id.rawValue,
            positionTicks: positionTicks
        )
    }

    public func reportPlaybackProgress(item: MediaItem, position: TimeInterval) async throws {
        let client = try client()
        let positionTicks = Int64(position * 10_000_000)
        try await client.reportPlaybackProgress(
            itemId: item.id.rawValue,
            positionTicks: positionTicks,
            isPaused: false
        )
    }

    public func reportPlaybackStopped(item: MediaItem, position: TimeInterval) async throws {
        let client = try client()
        let positionTicks = Int64(position * 10_000_000)
        try await client.reportPlaybackStopped(
            itemId: item.id.rawValue,
            positionTicks: positionTicks
        )
    }

    // MARK: - DownloadableProvider (Phase 6)

    public func downloadURL(for item: MediaItem, profile: DeviceProfile?) async throws -> URL {
        let client = try client()

        // Use the native download endpoint
        guard let url = client.downloadURL(itemId: item.id.rawValue) else {
            throw AppError.downloadFailed(
                itemTitle: item.title,
                reason: "Unable to build download URL"
            )
        }
        return url
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
