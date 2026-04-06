import Foundation

/// Typed provider IDs for external services (IMDB, TMDB, TVDB).
public struct ProviderIds: Hashable, Codable, Sendable {
    public let imdb: String?
    public let tmdb: String?
    public let tvdb: String?

    public init(imdb: String? = nil, tmdb: String? = nil, tvdb: String? = nil) {
        self.imdb = imdb
        self.tmdb = tmdb
        self.tvdb = tvdb
    }

    /// Creates typed provider IDs from the raw dictionary returned by Jellyfin.
    public init(raw: [String: String]?) {
        self.imdb = raw?["Imdb"]
        self.tmdb = raw?["Tmdb"]
        self.tvdb = raw?["Tvdb"]
    }

    /// Whether any provider ID is available.
    public var hasAny: Bool {
        imdb != nil || tmdb != nil || tvdb != nil
    }

    /// The IMDB URL, if an IMDB ID is available.
    public var imdbURL: URL? {
        imdb.flatMap { URL(string: "https://www.imdb.com/title/\($0)") }
    }

    /// The TMDB movie URL, if a TMDB ID is available.
    public func tmdbURL(for mediaType: MediaType) -> URL? {
        guard let id = tmdb else { return nil }
        switch mediaType {
        case .series:
            return URL(string: "https://www.themoviedb.org/tv/\(id)")
        default:
            return URL(string: "https://www.themoviedb.org/movie/\(id)")
        }
    }

    /// The TVDB URL, if a TVDB ID is available.
    public var tvdbURL: URL? {
        tvdb.flatMap { URL(string: "https://www.thetvdb.com/dereferrer/series/\($0)") }
    }
}
