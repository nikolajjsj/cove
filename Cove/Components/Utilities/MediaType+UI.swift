import Models
import SwiftUI

// MARK: - UI Helpers for MediaType

extension MediaType {

    /// The SF Symbol name used as a placeholder icon when artwork is unavailable.
    var placeholderIcon: String {
        switch self {
        case .movie: "film"
        case .series: "tv"
        case .episode: "play.rectangle"
        case .album: "music.note"
        case .artist: "person"
        case .track: "music.note"
        case .playlist: "music.note.list"
        case .collection: "rectangle.stack.fill"
        case .season: "tv"
        case .book: "book"
        case .podcast: "mic"
        case .genre: "guitars"
        }
    }

    /// Whether this media type represents music content (square artwork, etc.).
    var isMusic: Bool {
        switch self {
        case .album, .track, .artist, .playlist: true
        default: false
        }
    }

    /// Whether this media type represents video content (movies, series, episodes, seasons).
    var isVideo: Bool {
        switch self {
        case .movie, .series, .episode, .season: true
        default: false
        }
    }

    /// A user-facing display label for this media type.
    var displayLabel: String {
        switch self {
        case .movie: "Movie"
        case .series: "TV Show"
        case .episode: "Episode"
        case .season: "Season"
        case .album: "Album"
        case .artist: "Artist"
        case .track: "Song"
        case .playlist: "Playlist"
        case .collection: "Collection"
        case .genre: "Genre"
        case .book: "Book"
        case .podcast: "Podcast"
        }
    }
}
