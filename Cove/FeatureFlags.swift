/// Switches for work that exists in the tree but is not finished.
///
/// These are compile-time constants rather than user settings: they hide things
/// that are not ready, not things anyone should be choosing between.
enum FeatureFlags {
    /// Music browsing is hidden until music playback actually works.
    ///
    /// Shipping a Music tab that lists albums nobody can play is worse than not
    /// offering music at all, so music libraries are filtered out of the
    /// library list — which removes the Music tab, the Home rails, and the
    /// Settings entry together — and music results are dropped from search.
    ///
    /// Nothing under `Views/Music` was deleted. Flipping this to `true` brings
    /// all of it back.
    static let musicEnabled = false
}
