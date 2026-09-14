/// Switches for work that exists in the tree but is not finished.
///
/// These are compile-time constants rather than user settings: they hide things
/// that are not ready, not things anyone should be choosing between.
enum FeatureFlags {
    /// Grids read the local catalogue instead of calling the server.
    ///
    /// The sync engine runs either way; this only decides which source a view
    /// reads. Off, every view falls back to the provider exactly as before — the
    /// escape hatch the staged plan promised.
    static let localCatalogEnabled = true
}
