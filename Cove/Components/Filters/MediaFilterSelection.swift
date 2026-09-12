import SwiftUI

/// The set of filters a media list can apply, as a bundle of bindings.
///
/// Groups what used to be five separate bindings threaded through every filter
/// view, so the menu and the active-filter row can be described once and reused
/// by both the library grid and search.
struct MediaFilterSelection {
    @Binding var watched: WatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var decade: Decade?
    @Binding var minRating: Double?
    @Binding var genres: Set<String>

    /// Genres offered by the current library. Empty hides the genre section.
    var availableGenres: [String] = []

    /// Whether genre, decade, and rating apply. Music libraries only filter by
    /// watched state and favourites.
    var includesVideoFilters: Bool = true

    init(
        watched: Binding<WatchedFilter>,
        favoritesOnly: Binding<Bool>,
        decade: Binding<Decade?> = .constant(nil),
        minRating: Binding<Double?> = .constant(nil),
        genres: Binding<Set<String>> = .constant([]),
        availableGenres: [String] = [],
        includesVideoFilters: Bool = true
    ) {
        _watched = watched
        _favoritesOnly = favoritesOnly
        _decade = decade
        _minRating = minRating
        _genres = genres
        self.availableGenres = availableGenres
        self.includesVideoFilters = includesVideoFilters
    }

    // MARK: - Active state

    /// The filters currently narrowing the results, in the order they are shown.
    ///
    /// Each carries how to undo just itself, so the active-filter row can offer
    /// per-filter removal without every call site re-deriving it.
    var active: [ActiveMediaFilter] {
        var result: [ActiveMediaFilter] = []

        if watched != .all {
            result.append(
                ActiveMediaFilter(id: "watched", label: watched.label, systemImage: watched.systemImage) {
                    watched = .all
                })
        }
        if favoritesOnly {
            result.append(
                ActiveMediaFilter(id: "favorites", label: "Favorites", systemImage: "heart.fill") {
                    favoritesOnly = false
                })
        }
        for genre in genres.sorted() {
            result.append(
                ActiveMediaFilter(id: "genre-\(genre)", label: genre, systemImage: "tag.fill") {
                    genres.remove(genre)
                })
        }
        if let decade {
            result.append(
                ActiveMediaFilter(id: "decade", label: decade.rawValue, systemImage: "calendar") {
                    self.decade = nil
                })
        }
        if let minRating {
            result.append(
                ActiveMediaFilter(
                    id: "rating", label: "\(Int(minRating))+", systemImage: "star.fill"
                ) {
                    self.minRating = nil
                })
        }
        return result
    }

    var isActive: Bool { !active.isEmpty }

    func clear() {
        watched = .all
        favoritesOnly = false
        decade = nil
        minRating = nil
        genres = []
    }
}

/// One applied filter, and how to remove it.
struct ActiveMediaFilter: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let remove: () -> Void
}
