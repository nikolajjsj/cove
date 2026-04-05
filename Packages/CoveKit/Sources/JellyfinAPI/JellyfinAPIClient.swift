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
