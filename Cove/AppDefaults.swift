import Defaults
import Foundation
import Models

extension Defaults.Keys {

    // MARK: - Downloads

    /// Whether downloads are allowed over cellular connections.
    /// When `false` (the default), downloads only proceed on WiFi.
    static let downloadOverCellular = Key<Bool>("downloadOverCellular", default: false)

    // MARK: - Video Playback

    /// Default playback speed (1.0 = normal). Persisted across sessions.
    static let videoPlaybackSpeed = Key<Float>("videoPlaybackSpeed", default: 1.0)

    /// Maximum streaming quality for video playback.
    /// "auto" uses the default device profile (120 Mbps, effectively direct play).
    static let maxStreamingQuality = Key<StreamingQuality>("maxStreamingQuality", default: .auto)

    /// Whether to automatically play the next episode when the current one ends.
    static let autoPlayNextEpisode = Key<Bool>("autoPlayNextEpisode", default: true)

    /// Whether to force landscape orientation during video playback (iOS).
    static let forceLandscapeVideo = Key<Bool>("forceLandscapeVideo", default: true)

    /// Default skip-forward interval in seconds.
    static let skipForwardInterval = Key<Double>("skipForwardInterval", default: 10.0)

    /// Default skip-backward interval in seconds.
    static let skipBackwardInterval = Key<Double>("skipBackwardInterval", default: 10.0)

    /// The accent color name. Values: "default", "indigo", "purple", "pink", "red", "orange", "teal", "green".
    static let accentColor = Key<String>("accentColor", default: "default")

    // MARK: - Subtitle Appearance

    /// The size of subtitle text during video playback.
    static let subtitleSize = Key<SubtitleSize>("subtitleSize", default: .medium)

    /// The color of subtitle text during video playback.
    static let subtitleColor = Key<SubtitleColor>("subtitleColor", default: .white)

    /// The background style applied to subtitle text during video playback.
    static let subtitleBackground = Key<SubtitleBackground>("subtitleBackground", default: .outline)

    // MARK: - OpenSubtitles

    /// Ordered list of recently-used subtitle language codes (ISO 639-1).
    /// Most recently used language is first. Used to pin preferred languages
    /// at the top of the language picker in the subtitle search sheet.
    static let openSubtitlesRecentLanguages = Key<[String]>(
        "openSubtitlesRecentLanguages", default: [])

    // MARK: - Library Display

    /// Controls the density of media item grids (compact, regular, or large).
    static let gridDensity = Key<GridDensity>("gridDensity", default: .regular)

    /// The preferred layout for video library views (grid or list).
    static let videoLibraryLayout = Key<LibraryLayoutMode>("videoLibraryLayout", default: .grid)

    /// The preferred layout for music library views (grid or list).
    static let musicLibraryLayout = Key<LibraryLayoutMode>("musicLibraryLayout", default: .grid)

    // MARK: - Home Screen

    /// Ordered list of home screen sections with visibility toggles.
    /// Users can reorder and show/hide sections via the customization sheet.
    static let homeSections = Key<[HomeSectionConfig]>(
        "homeSections",
        default: HomeSectionConfig.defaultSections
    )
}

// MARK: - Defaults Conformance

extension StreamingQuality: Defaults.Serializable {}
extension GridDensity: Defaults.Serializable {}
extension LibraryLayoutMode: Defaults.Serializable {}
