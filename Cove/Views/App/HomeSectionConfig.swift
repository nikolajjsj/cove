import Defaults
import Foundation

/// Identifies a section on the home screen.
///
/// Each case maps to a specific content rail or banner in ``HomeView``.
/// The raw value is used as a stable persistence key in `AppDefaults`.
enum HomeSection: String, CaseIterable, Codable, Sendable, Defaults.Serializable {
    case heroBanner = "heroBanner"
    case continueWatching = "continueWatching"
    case upNext = "upNext"
    case movies = "movies"
    case tvShows = "tvShows"
    case collections = "collections"
    case genres = "genres"
    case becauseYouWatched = "becauseYouWatched"
    case recentlyAdded = "recentlyAdded"

    /// Human-readable display name shown in the customization sheet.
    var displayName: String {
        switch self {
        case .heroBanner: "Hero Banner"
        case .continueWatching: "Continue Watching"
        case .upNext: "Up Next"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .collections: "Collections"
        case .genres: "Genres"
        case .becauseYouWatched: "Because You Watched"
        case .recentlyAdded: "Recently Added"
        }
    }

    /// SF Symbol used in the customization sheet row.
    var systemImage: String {
        switch self {
        case .heroBanner: "star.fill"
        case .continueWatching: "play.circle"
        case .upNext: "sparkles.tv"
        case .movies: "film"
        case .tvShows: "tv"
        case .collections: "rectangle.stack"
        case .genres: "tag"
        case .becauseYouWatched: "heart.text.clipboard"
        case .recentlyAdded: "clock"
        }
    }
}

/// A single entry in the user's ordered home-section list.
///
/// Persisted as a `Codable` array in `AppDefaults.Keys.homeSections`.
/// The order of entries in the array determines display order;
/// `isVisible` controls whether the section is shown.
struct HomeSectionConfig: Codable, Equatable, Sendable, Defaults.Serializable {
    /// Which home section this entry represents.
    let section: HomeSection

    /// Whether the section is currently shown on the home screen.
    var isVisible: Bool

    /// The default configuration used on first launch or after a reset.
    static let defaultSections: [HomeSectionConfig] = [
        HomeSectionConfig(section: .heroBanner, isVisible: true),
        HomeSectionConfig(section: .continueWatching, isVisible: true),
        HomeSectionConfig(section: .upNext, isVisible: true),
        HomeSectionConfig(section: .genres, isVisible: true),
        HomeSectionConfig(section: .movies, isVisible: true),
        HomeSectionConfig(section: .tvShows, isVisible: true),
        HomeSectionConfig(section: .collections, isVisible: true),
        HomeSectionConfig(section: .becauseYouWatched, isVisible: true),
        HomeSectionConfig(section: .recentlyAdded, isVisible: true),
    ]
}
