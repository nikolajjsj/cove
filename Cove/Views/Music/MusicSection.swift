import Defaults
import Foundation

/// Identifies a section on the music library screen.
///
/// Each case maps to a specific content rail or shelf in `MusicLibraryView`.
/// The raw value is used as a stable persistence key in `AppDefaults`.
enum MusicSection: String, ConfigurableSection {
    case recentlyPlayed = "recentlyPlayed"
    case recentlyAdded = "recentlyAdded"
    case smartPlaylists = "smartPlaylists"
    case mostPlayed = "mostPlayed"
    case artists = "artists"
    case genres = "genres"
    case playlists = "playlists"
    case albums = "albums"

    /// Human-readable display name shown in the customization sheet.
    var displayName: String {
        switch self {
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .smartPlaylists: "Made for You"
        case .mostPlayed: "Most Played"
        case .artists: "Artists"
        case .genres: "Genres"
        case .playlists: "Playlists"
        case .albums: "Albums"
        }
    }

    /// SF Symbol used in the customization sheet row.
    var systemImage: String {
        switch self {
        case .recentlyPlayed: "play.circle"
        case .recentlyAdded: "clock"
        case .smartPlaylists: "wand.and.stars"
        case .mostPlayed: "chart.bar"
        case .artists: "music.mic"
        case .genres: "tag"
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        }
    }

    /// The default section order and visibility for first launch or reset.
    static var defaultConfigurations: [SectionConfig<MusicSection>] {
        [
            SectionConfig(section: .recentlyPlayed, isVisible: true),
            SectionConfig(section: .recentlyAdded, isVisible: true),
            SectionConfig(section: .smartPlaylists, isVisible: true),
            SectionConfig(section: .mostPlayed, isVisible: true),
            SectionConfig(section: .artists, isVisible: true),
            SectionConfig(section: .genres, isVisible: true),
            SectionConfig(section: .playlists, isVisible: true),
            SectionConfig(section: .albums, isVisible: true),
        ]
    }
}
