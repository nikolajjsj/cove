import Foundation
import Models

/// A lightweight async/await wrapper around URLSession.
/// Handles request building, JSON decoding, auth header injection, error mapping,
/// and response caching.
public final class HTTPClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let responseCache: ResponseCache

    public init(
        session: URLSession = HTTPClient.makeDefaultSession(),
        decoder: JSONDecoder = {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            d.dateDecodingStrategy = .iso8601
            return d
        }(),
        encoder: JSONEncoder = {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            e.dateEncodingStrategy = .iso8601
            return e
        }(),
        responseCache: ResponseCache = ResponseCache()
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.responseCache = responseCache
    }

    // MARK: - Default Session Factory

    /// Creates a `URLSession` with a generously-sized `URLCache` so that
    /// HTTP-level caching (ETag / Cache-Control) works out of the box.
    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB in memory
            diskCapacity: 200 * 1024 * 1024  // 200 MB on disk
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }

    // MARK: - Request Execution

    /// Execute a request and decode the JSON response body.
    public func request<T: Decodable & Sendable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        cachePolicy: CachePolicy = .networkOnly
    ) async throws -> T {
        let data = try await execute(
            url: url, method: method, headers: headers, body: body,
            queryItems: queryItems, cachePolicy: cachePolicy)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.unknown(underlying: error)
        }
    }

    /// Execute a request with a pre-encoded JSON body (bypasses the shared encoder).
    ///
    /// Use this when the request body requires a specific encoding strategy
    /// (e.g. PascalCase keys for Jellyfin API) that differs from the client's
    /// default `.convertToSnakeCase` encoder.
    public func request<T: Decodable & Sendable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        rawBody: Data,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let data = try await execute(
            url: url, method: method, headers: headers, rawBody: rawBody,
            queryItems: queryItems, cachePolicy: .networkOnly)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.unknown(underlying: error)
        }
    }

    /// Execute a request and discard the response body.
    public func request(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        cachePolicy: CachePolicy = .networkOnly
    ) async throws {
        _ = try await execute(
            url: url, method: method, headers: headers, body: body,
            queryItems: queryItems, cachePolicy: cachePolicy)
    }

    /// Execute a request and return raw Data.
    public func requestData(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        cachePolicy: CachePolicy = .networkOnly
    ) async throws -> Data {
        try await execute(
            url: url, method: method, headers: headers, body: body,
            queryItems: queryItems, cachePolicy: cachePolicy)
    }

    // MARK: - Cache Management

    /// The underlying response cache, exposed for targeted invalidation.
    ///
    /// Example:
    /// ```
    /// await httpClient.cache.removeAll(matching: "Items")
    /// ```
    public var cache: ResponseCache { responseCache }

    /// Convenience: clear every cached response.
    public func clearCache() async {
        await responseCache.removeAll()
    }

    // MARK: - Private

    private func execute(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        rawBody: Data,
        queryItems: [URLQueryItem]?,
        cachePolicy: CachePolicy
    ) async throws -> Data {
        try await execute(
            url: url, method: method, headers: headers,
            resolvedBody: rawBody, queryItems: queryItems, cachePolicy: cachePolicy)
    }

    private func execute(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]?,
        cachePolicy: CachePolicy
    ) async throws -> Data {
        let resolvedBody: Data?
        if let body {
            resolvedBody = try encoder.encode(body)
        } else {
            resolvedBody = nil
        }
        return try await execute(
            url: url, method: method, headers: headers,
            resolvedBody: resolvedBody, queryItems: queryItems, cachePolicy: cachePolicy)
    }

    private func execute(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        resolvedBody: Data?,
        queryItems: [URLQueryItem]?,
        cachePolicy: CachePolicy
    ) async throws -> Data {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryItems, !queryItems.isEmpty {
            let existing = urlComponents?.queryItems ?? []
            urlComponents?.queryItems = existing + queryItems
        }

        guard let finalURL = urlComponents?.url else {
            throw AppError.serverUnreachable(url: url)
        }

        // --- In-memory cache: check for a hit ---
        let cacheKey = finalURL.absoluteString

        if case .cacheFirst(let maxAge) = cachePolicy, method == .get {
            if let cached = await responseCache.get(forKey: cacheKey, maxAge: maxAge) {
                return cached
            }
        }

        // --- Build the URLRequest ---
        var urlRequest = URLRequest(url: finalURL)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let resolvedBody {
            urlRequest.httpBody = resolvedBody
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // --- Perform the network request ---
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw AppError.networkUnavailable
            case .cannotFindHost, .cannotConnectToHost, .timedOut:
                throw AppError.serverUnreachable(url: url)
            default:
                throw AppError.unknown(underlying: urlError)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.unknown(underlying: URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            // --- In-memory cache: store successful GET responses ---
            if case .cacheFirst = cachePolicy, method == .get {
                await responseCache.set(data, forKey: cacheKey)
            }
            return data
        case 401:
            throw AppError.authExpired(serverName: url.host ?? url.absoluteString)
        case 403:
            throw AppError.authFailed(reason: "Access denied")
        case 404:
            throw AppError.serverError(statusCode: 404, message: "Not found")
        default:
            let message = String(data: data, encoding: .utf8)
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
