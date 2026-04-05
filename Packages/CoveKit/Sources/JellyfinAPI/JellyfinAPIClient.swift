import Foundation
import Models
import Networking
import os

/// Lean, hand-rolled Jellyfin API client.
/// Only implements the endpoints we actually use.
public final class JellyfinAPIClient: Sendable {
    private let httpClient: HTTPClient
    private let baseURL: URL
    private let logger = Logger(subsystem: "com.nikolajjsj.jellyfin", category: "JellyfinAPI")

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
        return try await httpClient.request(url: url, method: .get, headers: authHeaders)
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
        isFavorite: Bool? = nil
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

        logger.debug("Fetching items for user \(userId)")
        return try await httpClient.request(
            url: url, method: .get, headers: authHeaders, queryItems: queryItems)
    }

    /// Get a single item's full details.
    /// `GET /Users/{userId}/Items/{itemId}`
    public func getItem(userId: String, itemId: String) async throws -> BaseItemDto {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)")
        let fields = [
            "Overview", "Genres", "DateCreated", "UserData", "CommunityRating", "OfficialRating",
            "ProductionYear", "People",
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
    public func getPlaybackInfo(userId: String, itemId: String) async throws -> PlaybackInfoResponse
    {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")
        let body = PlaybackInfoRequest(userId: userId)
        return try await httpClient.request(
            url: url, method: .post, headers: authHeaders, body: body)
    }

    /// Build a direct video stream URL. Synchronous.
    /// `GET /Videos/{id}/stream`
    public func videoStreamURL(itemId: String, mediaSourceId: String, container: String? = nil)
        -> URL?
    {
        guard let token = accessToken else { return nil }
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemId)/stream"),
            resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "static", value: "true"),
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

    enum CodingKeys: String, CodingKey {
        case userId = "userid"
    }
}
