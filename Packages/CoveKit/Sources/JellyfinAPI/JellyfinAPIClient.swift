import Foundation
import Models
import Networking
import os

/// Lean, hand-rolled Jellyfin API client.
/// Only implements the endpoints we actually use.
public final class JellyfinAPIClient: Sendable {
    public let httpClient: HTTPClient
    public let baseURL: URL
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "JellyfinAPI")

    /// Encoder that preserves PascalCase CodingKeys exactly as written.
    /// The shared HTTPClient encoder uses `.convertToSnakeCase`, which mangles
    /// PascalCase keys like `"DirectPlayProfiles"` → `"direct_play_profiles"`.
    /// The Jellyfin API expects PascalCase, so PlaybackInfo requests use this instead.
    private static let pascalCaseEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// The current access token, set after successful authentication.
    /// Thread-safe via nonisolated(unsafe) + Sendable container.
    private let tokenStore: TokenStore
    private let userIdStore: TokenStore

    public init(baseURL: URL, httpClient: HTTPClient = HTTPClient()) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.tokenStore = TokenStore()
        self.userIdStore = TokenStore()
    }

    /// Set the access token for authenticated requests.
    public func setAccessToken(_ token: String?) {
        tokenStore.set(token)
    }

    /// The current access token, if any.
    public var accessToken: String? {
        tokenStore.get()
    }

    /// Set the user ID for authenticated requests.
    public func setUserId(_ userId: String?) {
        userIdStore.set(userId)
    }

    /// The current user ID, if any.
    public var userId: String? {
        userIdStore.get()
    }

    // MARK: - Auth Headers

    private var authHeaders: [String: String] {
        [JellyfinAuthHeader.headerName: JellyfinAuthHeader.headerValue(token: tokenStore.get())]
    }

    // MARK: - Server Discovery

    /// Discover server info (pre-authentication).
    /// `GET /System/Info/Public`
    public func getPublicSystemInfo() async throws -> PublicSystemInfo {
        let url = baseURL.appendingPathComponent("System/Info/Public")
        logger.debug("Fetching public system info from \(url.absoluteString)")
        return try await httpClient.request(
            url: url,
            method: .get,
            headers: [JellyfinAuthHeader.headerName: JellyfinAuthHeader.headerValue(token: nil)]
        )
    }

    // MARK: - Authentication

    /// Authenticate with username and password.
    /// `POST /Users/AuthenticateByName`
    public func authenticateByName(username: String, password: String) async throws
        -> AuthenticationResult
    {
        let url = baseURL.appendingPathComponent("Users/AuthenticateByName")
        let body = AuthenticateByNameRequest(username: username, password: password)
        logger.debug("Authenticating user '\(username)' at \(url.absoluteString)")

        let result: AuthenticationResult = try await httpClient.request(
            url: url,
            method: .post,
            headers: [JellyfinAuthHeader.headerName: JellyfinAuthHeader.headerValue(token: nil)],
            body: body
        )

        // Store the token for subsequent requests
        if let token = result.accessToken {
            tokenStore.set(token)
            logger.info("Authentication successful, token stored")
        }

        // Store the user ID for subsequent requests
        if let userId = result.user?.id {
            userIdStore.set(userId)
        }

        return result
    }

    // MARK: - Libraries

    /// List virtual folders (libraries).
    /// `GET /Library/VirtualFolders`
    public func getVirtualFolders() async throws -> [VirtualFolderInfo] {
        let url = baseURL.appendingPathComponent("Library/VirtualFolders")
        logger.debug("Fetching virtual folders")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders)
    }

    // MARK: - Items

    /// Browse items with filtering and sorting.
    /// `GET /Users/{userId}/Items`
    public func getItems(
        userId: String,
        parentId: String? = nil,
        includeItemTypes: [String]? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        recursive: Bool = true,
        fields: [String] = [
            "Overview", "Genres", "DateCreated", "UserData", "CommunityRating", "OfficialRating",
            "ProductionYear",
        ],
        searchTerm: String? = nil,
        isFavorite: Bool? = nil,
        isPlayed: Bool? = nil,
        genres: [String]? = nil,
        personIds: [String]? = nil
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false"),
            URLQueryItem(name: "Fields", value: fields.joined(separator: ",")),
        ]

        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let includeItemTypes {
            queryItems.append(
                URLQueryItem(
                    name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")))
        }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy)) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex {
            queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let searchTerm { queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm)) }
        if let isFavorite {
            queryItems.append(
                URLQueryItem(name: "IsFavorite", value: isFavorite ? "true" : "false"))
        }
        if let isPlayed {
            queryItems.append(
                URLQueryItem(name: "IsPlayed", value: isPlayed ? "true" : "false"))
        }
        if let genres {
            queryItems.append(
                URLQueryItem(name: "Genres", value: genres.joined(separator: "|")))
        }
        if let personIds {
            queryItems.append(
                URLQueryItem(name: "PersonIds", value: personIds.joined(separator: ",")))
        }

        logger.debug(
            "Fetching \(includeItemTypes?.joined(separator: ", ") ?? "items") for user \(userId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Get a single item's full details.
    /// `GET /Users/{userId}/Items/{itemId}`
    public func getItem(userId: String, itemId: String) async throws -> BaseItemDto {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)")
        let fields = [
            "Overview", "Genres", "DateCreated", "UserData", "CommunityRating", "OfficialRating",
            "ProductionYear", "People", "RemoteTrailers", "ProviderIds", "Studios", "Taglines",
            "OriginalTitle", "EndDate", "MediaSources", "PremiereDate",
        ]
        let queryItems = [URLQueryItem(name: "Fields", value: fields.joined(separator: ","))]
        logger.debug("Fetching item \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    // MARK: - Image URLs

    /// Build an image URL for an item. This is synchronous — no network call.
    public func imageURL(
        itemId: String, imageType: String, maxWidth: Int? = nil, maxHeight: Int? = nil,
        tag: String? = nil
    ) -> URL? {
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemId)/Images/\(imageType)"),
            resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: String(maxWidth)))
        }
        if let maxHeight {
            queryItems.append(URLQueryItem(name: "maxHeight", value: String(maxHeight)))
        }
        if let tag { queryItems.append(URLQueryItem(name: "tag", value: tag)) }
        if !queryItems.isEmpty { urlComponents?.queryItems = queryItems }
        return urlComponents?.url
    }

    // MARK: - Artists

    /// List album artists.
    /// `GET /Artists/AlbumArtists`
    public func getAlbumArtists(
        userId: String,
        parentId: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        searchTerm: String? = nil
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Artists/AlbumArtists")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,Genres,DateCreated,UserData,SortName"),
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy)) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex {
            queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let searchTerm {
            queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        logger.debug("Fetching album artists for user \(userId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// List all artists.
    /// `GET /Artists`
    public func getArtists(
        userId: String,
        parentId: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        limit: Int? = nil,
        startIndex: Int? = nil,
        searchTerm: String? = nil
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Artists")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,Genres,DateCreated,UserData,SortName"),
        ]
        if let parentId { queryItems.append(URLQueryItem(name: "ParentId", value: parentId)) }
        if let sortBy { queryItems.append(URLQueryItem(name: "SortBy", value: sortBy)) }
        if let sortOrder { queryItems.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        if let limit { queryItems.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex {
            queryItems.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let searchTerm {
            queryItems.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        logger.debug("Fetching artists for user \(userId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    // MARK: - Audio Streaming

    /// Build a universal audio stream URL for a track. This is synchronous — no network call.
    /// `GET /Audio/{id}/universal`
    public func audioStreamURL(
        itemId: String,
        container: String = "opus,mp3|mp3,aac,m4a|aac,m4b|aac,flac,webma,webm|webma,wav,ogg",
        maxStreamingBitrate: Int = 140_000_000,
        audioBitRate: Int? = nil,
        transcodingContainer: String = "mp3",
        transcodingProtocol: String = "http"
    ) -> URL? {
        guard let currentUserId = userId else { return nil }
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Audio/\(itemId)/universal"),
            resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: currentUserId),
            URLQueryItem(name: "Container", value: container),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(maxStreamingBitrate)),
            URLQueryItem(name: "TranscodingContainer", value: transcodingContainer),
            URLQueryItem(name: "TranscodingProtocol", value: transcodingProtocol),
            URLQueryItem(name: "api_key", value: token),
        ]
        if let audioBitRate {
            queryItems.append(URLQueryItem(name: "AudioBitRate", value: String(audioBitRate)))
        }
        urlComponents?.queryItems = queryItems
        return urlComponents?.url
    }

    // MARK: - Playback Reporting

    /// Report playback start.
    /// `POST /Sessions/Playing`
    public func reportPlaybackStart(
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("Sessions/Playing")
        let body = PlaybackStartInfo(
            itemId: itemId, positionTicks: positionTicks, mediaSourceId: mediaSourceId)
        logger.debug("Reporting playback start for item \(itemId)")
        try await httpClient.request(url: url, method: .post, headers: authHeaders, body: body)
    }

    /// Report playback progress.
    /// `POST /Sessions/Playing/Progress`
    public func reportPlaybackProgress(
        itemId: String,
        positionTicks: Int64,
        isPaused: Bool,
        mediaSourceId: String? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("Sessions/Playing/Progress")
        let body = PlaybackProgressInfo(
            itemId: itemId, positionTicks: positionTicks, mediaSourceId: mediaSourceId,
            isPaused: isPaused)
        logger.debug("Reporting playback progress for item \(itemId)")
        try await httpClient.request(url: url, method: .post, headers: authHeaders, body: body)
    }

    /// Report playback stopped.
    /// `POST /Sessions/Playing/Stopped`
    public func reportPlaybackStopped(
        itemId: String,
        positionTicks: Int64,
        mediaSourceId: String? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("Sessions/Playing/Stopped")
        let body = PlaybackStopInfo(
            itemId: itemId, positionTicks: positionTicks, mediaSourceId: mediaSourceId)
        logger.debug("Reporting playback stopped for item \(itemId)")
        try await httpClient.request(url: url, method: .post, headers: authHeaders, body: body)
    }

    // MARK: - Video Playback Info

    /// Get playback info for a video item (media sources, streams, transcode decisions).
    /// `POST /Items/{id}/PlaybackInfo`
    public func getPlaybackInfo(
        userId: String,
        itemId: String,
        profile: DeviceProfile? = nil
    ) async throws -> PlaybackInfoResponse {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")
        let body = PlaybackInfoRequest(
            userId: userId,
            deviceProfile: profile,
            autoOpenLiveStream: true,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            maxStreamingBitrate: profile?.maxStreamingBitrate
        )
        let rawBody = try Self.pascalCaseEncoder.encode(body)
        return try await httpClient.request(
            url: url, method: .post, headers: authHeaders, rawBody: rawBody)
    }

    /// Request playback info with direct play and direct stream disabled,
    /// forcing the server to provide a transcode URL.
    /// Used as a fallback when the server's initial response suggests direct play
    /// for a format AVPlayer cannot handle.
    public func getPlaybackInfoTranscodeOnly(
        userId: String,
        itemId: String,
        profile: DeviceProfile
    ) async throws -> PlaybackInfoResponse {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")
        let body = PlaybackInfoRequest(
            userId: userId,
            deviceProfile: profile,
            autoOpenLiveStream: true,
            enableDirectPlay: false,
            enableDirectStream: false,
            enableTranscoding: true,
            maxStreamingBitrate: profile.maxStreamingBitrate
        )
        let rawBody = try Self.pascalCaseEncoder.encode(body)
        return try await httpClient.request(
            url: url, method: .post, headers: authHeaders, rawBody: rawBody)
    }

    /// Build a video stream URL.
    /// - Parameter staticStream: `true` for direct play (raw file), `false` for direct stream (server remuxes).
    public func videoStreamURL(
        itemId: String,
        mediaSourceId: String,
        container: String? = nil,
        staticStream: Bool = true
    ) -> URL? {
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemId)/stream"),
            resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "static", value: staticStream ? "true" : "false"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "api_key", value: token),
        ]
        if let container {
            queryItems.append(URLQueryItem(name: "container", value: container))
        }
        urlComponents?.queryItems = queryItems
        return urlComponents?.url
    }

    /// Build an HLS transcode stream URL from a server-provided transcode path. Synchronous.
    public func hlsStreamURL(transcodingPath: String) -> URL? {
        guard !transcodingPath.isEmpty else { return nil }
        // The transcodingUrl from Jellyfin is a relative path like /videos/{id}/master.m3u8?...
        // It already contains all query params including the play session
        // We just need to prepend the base URL
        if let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            let fullURLString =
                "\(baseComponents.scheme ?? "http")://\(baseComponents.host ?? "")\(baseComponents.port.map { ":\($0)" } ?? "")\(transcodingPath)"
            return URL(string: fullURLString)
        }
        return nil
    }

    /// Build a subtitle stream URL. Synchronous.
    /// `GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.vtt`
    public func subtitleURL(
        itemId: String, mediaSourceId: String, subtitleIndex: Int, format: String = "vtt"
    ) -> URL? {
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent(
                "Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(subtitleIndex)/Stream.\(format)"),
            resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "api_key", value: token)]
        return urlComponents?.url
    }

    /// Build a download URL for a media item. Synchronous.
    /// For audio: uses the audio stream endpoint
    /// For video: uses the video stream endpoint with `static=true`
    /// `GET /Items/{id}/Download` (Jellyfin native download endpoint)
    public func downloadURL(itemId: String) -> URL? {
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemId)/Download"),
            resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "api_key", value: token)
        ]
        return urlComponents?.url
    }

    /// Build a download URL that requests a compatible format from the server.
    /// Uses the video stream endpoint with `static=false` so the server can remux/transcode.
    /// - Parameters:
    ///   - itemId: The item ID to download.
    ///   - mediaSourceId: The media source ID from PlaybackInfo.
    public func compatibleDownloadURL(
        itemId: String,
        mediaSourceId: String
    ) -> URL? {
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemId)/stream"),
            resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "static", value: "false"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "container", value: "mp4"),
            URLQueryItem(name: "api_key", value: token),
        ]
        return urlComponents?.url
    }

    // MARK: - Similar Items

    /// Get items similar to a given item.
    /// `GET /Items/{itemId}/Similar`
    public func getSimilarItems(
        itemId: String,
        userId: String,
        limit: Int? = nil,
        fields: [String] = [
            "Overview", "Genres", "UserData", "CommunityRating", "OfficialRating", "ProductionYear",
            "People",
        ]
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/Similar")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: fields.joined(separator: ",")),
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        logger.debug("Fetching similar items for \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    // MARK: - Special Features

    /// Get special features for an item (behind-the-scenes, deleted scenes, etc.).
    /// `GET /Users/{userId}/Items/{itemId}/SpecialFeatures`
    public func getSpecialFeatures(
        itemId: String,
        userId: String
    ) async throws -> [BaseItemDto] {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)/SpecialFeatures")
        logger.debug("Fetching special features for \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders)
    }

    // MARK: - Local Trailers

    /// Get local trailers for an item.
    /// `GET /Users/{userId}/Items/{itemId}/LocalTrailers`
    public func getLocalTrailers(
        itemId: String,
        userId: String
    ) async throws -> [BaseItemDto] {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)/LocalTrailers")
        logger.debug("Fetching local trailers for \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders)
    }

    // MARK: - Shows (TV Series)

    /// Get seasons for a series.
    /// `GET /Shows/{seriesId}/Seasons`
    public func getSeasons(seriesId: String, userId: String) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Shows/\(seriesId)/Seasons")
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,UserData,ChildCount"),
        ]
        logger.debug("Fetching seasons for series \(seriesId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Get episodes for a series, optionally filtered by season.
    /// `GET /Shows/{seriesId}/Episodes`
    public func getEpisodes(seriesId: String, seasonId: String? = nil, userId: String) async throws
        -> ItemsResult
    {
        let url = baseURL.appendingPathComponent("Shows/\(seriesId)/Episodes")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,UserData,DateCreated,MediaSources"),
        ]
        if let seasonId {
            queryItems.append(URLQueryItem(name: "SeasonId", value: seasonId))
        }
        logger.debug("Fetching episodes for series \(seriesId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Get "next up" episodes to watch.
    /// `GET /Shows/NextUp`
    public func getNextUp(userId: String, seriesId: String? = nil, limit: Int = 20) async throws
        -> ItemsResult
    {
        let url = baseURL.appendingPathComponent("Shows/NextUp")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,UserData,DateCreated"),
            URLQueryItem(name: "Limit", value: String(limit)),
        ]
        if let seriesId {
            queryItems.append(URLQueryItem(name: "SeriesId", value: seriesId))
        }
        logger.debug("Fetching next up episodes")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Get items to resume (continue watching).
    /// `GET /Users/{userId}/Items/Resume`
    public func getResumeItems(userId: String, mediaTypes: [String]? = nil, limit: Int = 12)
        async throws -> ItemsResult
    {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/Resume")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "Fields", value: "Overview,UserData,DateCreated"),
            URLQueryItem(name: "Limit", value: String(limit)),
        ]
        if let mediaTypes {
            queryItems.append(
                URLQueryItem(name: "MediaTypes", value: mediaTypes.joined(separator: ",")))
        }
        logger.debug("Fetching resume items for user \(userId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    // MARK: - Music Features

    /// Fetch lyrics for a track.
    /// Returns the raw lyrics response from `/Audio/{itemId}/Lyrics`.
    public func getLyrics(itemId: String) async throws -> LyricsResponse {
        let url = baseURL.appendingPathComponent("Audio/\(itemId)/Lyrics")
        logger.debug("Fetching lyrics for item \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders)
    }

    /// Mark an item as a favorite.
    public func addFavorite(userId: String, itemId: String) async throws {
        let url = baseURL.appendingPathComponent("Users/\(userId)/FavoriteItems/\(itemId)")
        logger.debug("Adding favorite for item \(itemId)")
        try await httpClient.request(
            url: url, method: .post, headers: authHeaders)
    }

    /// Remove an item from favorites.
    public func removeFavorite(userId: String, itemId: String) async throws {
        let url = baseURL.appendingPathComponent("Users/\(userId)/FavoriteItems/\(itemId)")
        logger.debug("Removing favorite for item \(itemId)")
        try await httpClient.request(
            url: url, method: .delete, headers: authHeaders)
    }

    // MARK: - Played Status

    /// Mark an item as played.
    public func markPlayed(userId: String, itemId: String) async throws {
        let url = baseURL.appendingPathComponent("Users/\(userId)/PlayedItems/\(itemId)")
        logger.debug("Marking item \(itemId) as played")
        try await httpClient.request(
            url: url, method: .post, headers: authHeaders)
    }

    /// Mark an item as unplayed.
    public func markUnplayed(userId: String, itemId: String) async throws {
        let url = baseURL.appendingPathComponent("Users/\(userId)/PlayedItems/\(itemId)")
        logger.debug("Marking item \(itemId) as unplayed")
        try await httpClient.request(
            url: url, method: .delete, headers: authHeaders)
    }

    /// Fetch an instant mix (radio) seeded from an item.
    public func getInstantMix(
        itemId: String,
        userId: String,
        limit: Int = 50
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/InstantMix")
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(
                name: "Fields", value: "Overview,Genres,DateCreated,UserData,ProductionYear"),
        ]
        logger.debug("Fetching instant mix for item \(itemId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems,
            cachePolicy: .networkOnly)
    }

    // MARK: - Playlist CRUD

    /// Create a new playlist.
    public func createPlaylist(
        userId: String,
        name: String,
        trackIds: [String] = []
    ) async throws -> CreatePlaylistResponse {
        let url = baseURL.appendingPathComponent("Playlists")
        let body = CreatePlaylistRequest(
            name: name,
            userId: userId,
            ids: trackIds,
            mediaType: "Audio"
        )
        let rawBody = try Self.pascalCaseEncoder.encode(body)
        logger.debug("Creating playlist '\(name)'")
        return try await httpClient.request(
            url: url, method: .post, headers: authHeaders, rawBody: rawBody)
    }

    /// Add tracks to an existing playlist.
    public func addToPlaylist(
        playlistId: String,
        trackIds: [String]
    ) async throws {
        let url = baseURL.appendingPathComponent("Playlists/\(playlistId)/Items")
        let queryItems = [
            URLQueryItem(name: "Ids", value: trackIds.joined(separator: ","))
        ]
        logger.debug("Adding \(trackIds.count) tracks to playlist \(playlistId)")
        try await httpClient.request(
            url: url, method: .post, headers: authHeaders, queryItems: queryItems)
    }

    /// Remove tracks from a playlist by their entry IDs.
    public func removeFromPlaylist(
        playlistId: String,
        entryIds: [String]
    ) async throws {
        let url = baseURL.appendingPathComponent("Playlists/\(playlistId)/Items")
        let queryItems = [
            URLQueryItem(name: "EntryIds", value: entryIds.joined(separator: ","))
        ]
        logger.debug("Removing \(entryIds.count) entries from playlist \(playlistId)")
        try await httpClient.request(
            url: url, method: .delete, headers: authHeaders, queryItems: queryItems)
    }

    /// Get items in a playlist.
    public func getPlaylistItems(
        playlistId: String,
        userId: String
    ) async throws -> ItemsResult {
        let url = baseURL.appendingPathComponent("Playlists/\(playlistId)/Items")
        let queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(
                name: "Fields", value: "Overview,Genres,DateCreated,UserData,ProductionYear"),
        ]
        logger.debug("Fetching items for playlist \(playlistId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Update an item (e.g., rename a playlist).
    public func updateItem(itemId: String, name: String) async throws {
        let url = baseURL.appendingPathComponent("Items/\(itemId)")
        let body = UpdateItemRequest(name: name)
        logger.debug("Updating item \(itemId) name to '\(name)'")
        try await httpClient.request(
            url: url, method: .post, headers: authHeaders, body: body)
    }

    /// Delete an item (e.g., delete a playlist).
    public func deleteItem(itemId: String) async throws {
        let url = baseURL.appendingPathComponent("Items/\(itemId)")
        logger.debug("Deleting item \(itemId)")
        try await httpClient.request(
            url: url, method: .delete, headers: authHeaders)
    }
}

// MARK: - Thread-safe token storage

/// A simple Sendable container for an optional string.
private final class TokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _token
    }

    func set(_ token: String?) {
        lock.lock()
        defer { lock.unlock() }
        _token = token
    }
}

// MARK: - Playback Reporting DTOs

/// Body for `POST /Sessions/Playing`.
private struct PlaybackStartInfo: Encodable, Sendable {
    let itemId: String
    let positionTicks: Int64
    let mediaSourceId: String?
    let playMethod: String

    init(itemId: String, positionTicks: Int64, mediaSourceId: String?) {
        self.itemId = itemId
        self.positionTicks = positionTicks
        self.mediaSourceId = mediaSourceId
        self.playMethod = "DirectPlay"
    }

    // All-lowercase string values so that the HTTPClient's convertToSnakeCase
    // encoder strategy passes them through unchanged. Jellyfin's server uses
    // case-insensitive JSON deserialization, so "itemid" matches "ItemId".
    enum CodingKeys: String, CodingKey {
        case itemId = "itemid"
        case positionTicks = "positionticks"
        case mediaSourceId = "mediasourceid"
        case playMethod = "playmethod"
    }
}

/// Body for `POST /Sessions/Playing/Progress`.
private struct PlaybackProgressInfo: Encodable, Sendable {
    let itemId: String
    let positionTicks: Int64
    let mediaSourceId: String?
    let playMethod: String
    let isPaused: Bool

    init(itemId: String, positionTicks: Int64, mediaSourceId: String?, isPaused: Bool) {
        self.itemId = itemId
        self.positionTicks = positionTicks
        self.mediaSourceId = mediaSourceId
        self.playMethod = "DirectPlay"
        self.isPaused = isPaused
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "itemid"
        case positionTicks = "positionticks"
        case mediaSourceId = "mediasourceid"
        case playMethod = "playmethod"
        case isPaused = "ispaused"
    }
}

/// Body for `POST /Sessions/Playing/Stopped`.
private struct PlaybackStopInfo: Encodable, Sendable {
    let itemId: String
    let positionTicks: Int64
    let mediaSourceId: String?
    let playMethod: String

    init(itemId: String, positionTicks: Int64, mediaSourceId: String?) {
        self.itemId = itemId
        self.positionTicks = positionTicks
        self.mediaSourceId = mediaSourceId
        self.playMethod = "DirectPlay"
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "itemid"
        case positionTicks = "positionticks"
        case mediaSourceId = "mediasourceid"
        case playMethod = "playmethod"
    }
}

/// Body for `POST /Items/{id}/PlaybackInfo`
private struct PlaybackInfoRequest: Encodable, Sendable {
    let userId: String
    let deviceProfile: DeviceProfile?
    let autoOpenLiveStream: Bool
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let maxStreamingBitrate: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case deviceProfile = "DeviceProfile"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
    }
}

// MARK: - Music Feature DTOs

/// Response from the lyrics endpoint.
public struct LyricsResponse: Codable, Sendable {
    public let lyrics: [LyricLineDto]?

    enum CodingKeys: String, CodingKey {
        case lyrics = "Lyrics"
    }
}

public struct LyricLineDto: Codable, Sendable {
    public let start: Int64?
    public let text: String?

    enum CodingKeys: String, CodingKey {
        case start = "Start"
        case text = "Text"
    }
}

/// Request body for creating a playlist.
struct CreatePlaylistRequest: Encodable, Sendable {
    let name: String
    let userId: String
    let ids: [String]
    let mediaType: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case userId = "UserId"
        case ids = "Ids"
        case mediaType = "MediaType"
    }
}

/// Response from creating a playlist.
public struct CreatePlaylistResponse: Codable, Sendable {
    public let id: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

/// Request body for updating an item name.
/// Uses lowercase coding keys so the HTTPClient's `.convertToSnakeCase`
/// encoder passes them through unchanged. Jellyfin's server uses
/// case-insensitive JSON deserialization, so "name" matches "Name".
struct UpdateItemRequest: Encodable, Sendable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
    }
}
