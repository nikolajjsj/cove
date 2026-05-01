import Foundation

// MARK: - Client

/// A client for the OpenSubtitles REST API v1.
public final class OpenSubtitlesClient: Sendable {
    private let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let apiKey: String?
    private let session: URLSession
    private let userAgent = "Cove v1.0"
    private let decoder = JSONDecoder()

    public init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Search

    /// Search for subtitles on OpenSubtitles.
    /// - Parameters:
    ///   - imdbId: IMDB ID (e.g. "tt0903747"). Preferred search method.
    ///   - query: Text query fallback (title + year).
    ///   - language: ISO 639-1 language code (e.g. "en", "da").
    ///   - page: Page number (default 1).
    /// - Returns: Search response with subtitle results.
    public func search(
        imdbId: String? = nil,
        query: String? = nil,
        language: String,
        page: Int = 1
    ) async throws -> SubtitleSearchResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "subtitles"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "languages", value: language),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "order_by", value: "download_count"),
            URLQueryItem(name: "order_direction", value: "desc"),
        ]
        if let imdbId {
            // OpenSubtitles expects numeric IMDB id without "tt" prefix
            let numericId = imdbId.replacing("tt", with: "")
            queryItems.append(URLQueryItem(name: "imdb_id", value: numericId))
        }
        if let query {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OpenSubtitlesError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        }

        let (data, response) = try await performRequest(request)
        try validateResponse(response)

        return try decoder.decode(SubtitleSearchResponse.self, from: data)
    }

    // MARK: - Download Link

    /// Request a download link for a subtitle file.
    /// - Parameter fileId: The file ID from search results.
    /// - Returns: Download response containing the temporary download URL.
    public func downloadLink(fileId: Int) async throws -> SubtitleDownloadResponse {
        let url = baseURL.appending(path: "download")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        }

        let body = ["file_id": fileId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response)

        return try decoder.decode(SubtitleDownloadResponse.self, from: data)
    }

    // MARK: - Download Subtitle Data

    /// Download the actual subtitle file content from a temporary link.
    /// - Parameter urlString: The temporary download URL from ``downloadLink(fileId:)``.
    /// - Returns: Raw subtitle file data.
    public func downloadSubtitleData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw OpenSubtitlesError.downloadFailed
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw OpenSubtitlesError.downloadFailed
        }

        guard !data.isEmpty else {
            throw OpenSubtitlesError.downloadFailed
        }

        return data
    }

    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws(OpenSubtitlesError) -> (
        Data, URLResponse
    ) {
        do {
            return try await session.data(for: request)
        } catch {
            throw OpenSubtitlesError.networkError(description: error.localizedDescription)
        }
    }

    private func validateResponse(_ response: URLResponse) throws(OpenSubtitlesError) {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw OpenSubtitlesError.unauthorized
        case 429:
            // The reset time might come from response headers
            let resetTime = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
            throw OpenSubtitlesError.rateLimited(resetTime: resetTime)
        default:
            throw OpenSubtitlesError.invalidResponse
        }
    }
}

// MARK: - Errors

public enum OpenSubtitlesError: Error, LocalizedError, Sendable {
    case rateLimited(resetTime: String?)
    case unauthorized
    case noResults
    case invalidResponse
    case networkError(description: String)
    case downloadFailed

    public var errorDescription: String? {
        switch self {
        case .rateLimited:
            "Too many requests. Please try again later."
        case .unauthorized:
            "Invalid API key. Please check your OpenSubtitles API key in Settings."
        case .noResults:
            "No subtitles found."
        case .invalidResponse:
            "Received an unexpected response from OpenSubtitles."
        case .networkError(let description):
            "Network error: \(description)"
        case .downloadFailed:
            "Failed to download the subtitle file."
        }
    }
}
