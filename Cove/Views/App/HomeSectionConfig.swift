import Defaults
import Foundation

/// Identifies a section on the home screen.
///
/// Each case maps to a specific content rail or banner in `HomeView`.
/// The raw value is used as a stable persistence key in `AppDefaults`.
enum HomeSection: String, ConfigurableSection {
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

    /// The default section order and visibility for first launch or reset.
    static var defaultConfigurations: [SectionConfig<HomeSection>] {
        [
            SectionConfig(section: .heroBanner, isVisible: true),
            SectionConfig(section: .continueWatching, isVisible: true),
            SectionConfig(section: .upNext, isVisible: true),
            SectionConfig(section: .genres, isVisible: true),
            SectionConfig(section: .movies, isVisible: true),
            SectionConfig(section: .tvShows, isVisible: true),
            SectionConfig(section: .collections, isVisible: true),
            SectionConfig(section: .becauseYouWatched, isVisible: true),
            SectionConfig(section: .recentlyAdded, isVisible: true),
        ]
    }
}
