import Models

// MARK: - Library Type Helpers

// `nonisolated`: the app target defaults to main-actor isolation, which would
// make this pure value logic unreachable from the @Sendable fetch closures that
// need it.
nonisolated extension MediaLibrary {
    /// Returns the Jellyfin `IncludeItemTypes` values appropriate for this library's collection type.
    /// This ensures TV Shows libraries return only Series (not Seasons/Episodes),
    /// Movies libraries return only Movies, etc.
    var includeItemTypes: [String]? {
        switch collectionType {
        case .movies:
            return ["Movie"]
        case .tvshows:
            return ["Series"]
        case .boxsets:
            return ["BoxSet"]
        default:
            return nil
        }
    }
}
