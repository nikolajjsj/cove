import Models
import SwiftUI

/// A hardcoded "smart playlist" preset that queries the Jellyfin server
/// using a specific filter + sort configuration, producing a dynamic track list.
///
/// Smart playlists are not user-editable — they are built-in presets that
/// surface interesting slices of the user's music library using the existing
/// Jellyfin query API with a high cache TTL so results stay stable.
struct SmartPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let gradientColors: [Color]
    let sortField: SortField
    let sortOrder: Models.SortOrder
    let limit: Int
    let isFavorite: Bool?
    let isPlayed: Bool?

    /// Cache TTL in seconds for the API response.
    /// Smart playlists use a high value so results don't change on every visit.
    let cacheMaxAge: TimeInterval

    // MARK: - Presets

    /// The complete list of built-in smart playlist presets.
    static let presets: [SmartPlaylist] = [
        // Your most played tracks — the songs on heavy repeat.
        SmartPlaylist(
            id: "heavyRotation",
            name: "Heavy Rotation",
            subtitle: "Your most played tracks",
            icon: "flame.fill",
            gradientColors: [
                Color(red: 0.96, green: 0.35, blue: 0.14),
                Color(red: 0.88, green: 0.12, blue: 0.22),
            ],
            sortField: .playCount,
            sortOrder: .descending,
            limit: 50,
            isFavorite: nil,
            isPlayed: nil,
            cacheMaxAge: 1800
        ),

        // Tracks you haven't listened to yet.
        SmartPlaylist(
            id: "unplayed",
            name: "Unplayed",
            subtitle: "Tracks you haven't heard yet",
            icon: "ear",
            gradientColors: [
                Color(red: 0.06, green: 0.72, blue: 0.52),
                Color(red: 0.04, green: 0.52, blue: 0.62),
            ],
            sortField: .random,
            sortOrder: .descending,
            limit: 50,
            isFavorite: nil,
            isPlayed: false,
            cacheMaxAge: 1800
        ),

        // Your favorites in a random order.
        SmartPlaylist(
            id: "favoritesMix",
            name: "Favorites Mix",
            subtitle: "Your favorites, shuffled",
            icon: "heart.fill",
            gradientColors: [
                Color(red: 0.92, green: 0.18, blue: 0.52),
                Color(red: 0.72, green: 0.10, blue: 0.68),
            ],
            sortField: .random,
            sortOrder: .descending,
            limit: 50,
            isFavorite: true,
            isPlayed: nil,
            cacheMaxAge: 1800
        ),

        // A completely random selection from the full library.
        SmartPlaylist(
            id: "random50",
            name: "Random 50",
            subtitle: "A random mix from your library",
            icon: "dice.fill",
            gradientColors: [
                Color(red: 0.38, green: 0.18, blue: 0.82),
                Color(red: 0.18, green: 0.40, blue: 0.95),
            ],
            sortField: .random,
            sortOrder: .descending,
            limit: 50,
            isFavorite: nil,
            isPlayed: nil,
            cacheMaxAge: 1800
        ),

        // Favorites you haven't listened to in a long time.
        SmartPlaylist(
            id: "forgottenFavorites",
            name: "Forgotten Favorites",
            subtitle: "Favorites you haven't played in a while",
            icon: "heart.slash",
            gradientColors: [
                Color(red: 0.82, green: 0.58, blue: 0.10),
                Color(red: 0.68, green: 0.32, blue: 0.08),
            ],
            sortField: .datePlayed,
            sortOrder: .ascending,
            limit: 40,
            isFavorite: true,
            isPlayed: nil,
            cacheMaxAge: 1800
        ),

        // Songs you've heard but barely — the overlooked gems.
        SmartPlaylist(
            id: "deepCuts",
            name: "Deep Cuts",
            subtitle: "Songs you've barely listened to",
            icon: "headphones",
            gradientColors: [
                Color(red: 0.10, green: 0.14, blue: 0.46),
                Color(red: 0.08, green: 0.38, blue: 0.42),
            ],
            sortField: .playCount,
            sortOrder: .ascending,
            limit: 50,
            isFavorite: nil,
            isPlayed: true,
            cacheMaxAge: 1800
        ),
    ]
}
