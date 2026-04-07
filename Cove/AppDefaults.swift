import Defaults
import Foundation

extension Defaults.Keys {
    /// Whether downloads are allowed over cellular connections.
    /// When `false` (the default), downloads only proceed on WiFi.
    static let downloadOverCellular = Key<Bool>("downloadOverCellular", default: false)

    // MARK: - Video Playback

    /// Default playback speed (1.0 = normal). Persisted across sessions.
    static let videoPlaybackSpeed = Key<Float>("videoPlaybackSpeed", default: 1.0)

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
}
