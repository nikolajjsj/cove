import Foundation

public enum MediaType: String, Codable, Sendable {
    case movie
    case series
    case season
    case episode
    case album
    case artist
    case track
    case playlist
    case collection
    case genre
    case book  // Future
    case podcast  // Future
}
