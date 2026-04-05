import Foundation
import Models

/// A lightweight async/await wrapper around URLSession.
/// Handles request building, JSON decoding, auth header injection, and error mapping.
public final class HTTPClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        session: URLSession = .shared,
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
        }()
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    // MARK: - Request Execution

    /// Execute a request and decode the JSON response body.
    public func request<T: Decodable & Sendable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let data = try await execute(
            url: url, method: method, headers: headers, body: body, queryItems: queryItems)
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
        queryItems: [URLQueryItem]? = nil
    ) async throws {
        _ = try await execute(
            url: url, method: method, headers: headers, body: body, queryItems: queryItems)
    }

    /// Execute a request and return raw Data.
    public func requestData(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        try await execute(
            url: url, method: method, headers: headers, body: body, queryItems: queryItems)
    }

    // MARK: - Private

    private func execute(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]?
    ) async throws -> Data {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryItems, !queryItems.isEmpty {
            let existing = urlComponents?.queryItems ?? []
            urlComponents?.queryItems = existing + queryItems
        }

        guard let finalURL = urlComponents?.url else {
            throw AppError.serverUnreachable(url: url)
        }

        var urlRequest = URLRequest(url: finalURL)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

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
