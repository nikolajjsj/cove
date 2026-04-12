import Foundation

// MARK: - Search Response

/// Top-level response from `GET /subtitles`.
public struct SubtitleSearchResponse: Codable, Sendable {
    public let totalPages: Int
    public let totalCount: Int
    public let page: Int
    public let data: [SubtitleResult]

    enum CodingKeys: String, CodingKey {
        case totalPages = "total_pages"
        case totalCount = "total_count"
        case page
        case data
    }
}

public struct SubtitleResult: Codable, Sendable, Identifiable {
    public let id: String
    public let attributes: SubtitleAttributes
}

public struct SubtitleAttributes: Codable, Sendable {
    public let subtitleId: String
    public let language: String
    public let downloadCount: Int
    public let hearingImpaired: Bool
    public let release: String
    public let files: [SubtitleFile]

    enum CodingKeys: String, CodingKey {
        case subtitleId = "subtitle_id"
        case language
        case downloadCount = "download_count"
        case hearingImpaired = "hearing_impaired"
        case release
        case files
    }
}

public struct SubtitleFile: Codable, Sendable {
    public let fileId: Int
    public let fileName: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
    }
}

// MARK: - Download Response

/// Response from `POST /download`.
public struct SubtitleDownloadResponse: Codable, Sendable {
    public let link: String
    public let fileName: String
    public let requests: Int
    public let remaining: Int
    public let message: String?
    public let resetTime: String?
    public let resetTimeUtc: String?

    enum CodingKeys: String, CodingKey {
        case link
        case fileName = "file_name"
        case requests
        case remaining
        case message
        case resetTime = "reset_time"
        case resetTimeUtc = "reset_time_utc"
    }
}
