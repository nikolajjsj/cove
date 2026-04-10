import Models

// MARK: - Music Browse Routes

/// Routes for "See All" navigation from the music library shelves.
/// Registered in the centralized `NavigationDestinations` modifier so
/// all navigation goes through `NavigationLink(value:)` — no inline destinations.
enum MusicBrowseRoute: Hashable {
    case allArtists(libraryId: ItemID)
    case allAlbums(libraryId: ItemID)
}
