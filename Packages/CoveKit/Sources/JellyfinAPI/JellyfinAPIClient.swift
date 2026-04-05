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

    public init(baseURL: URL, httpClient: HTTPClient = HTTPClient()) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.tokenStore = TokenStore()
    }

    /// Set the access token for authenticated requests.
    public func setAccessToken(_ token: String?) {
        tokenStore.set(token)
    }

    /// The current access token, if any.
    public var accessToken: String? {
        tokenStore.get()
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

        return result
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
