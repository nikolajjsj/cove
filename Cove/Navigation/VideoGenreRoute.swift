import Models

/// Route for navigating to a video genre detail view (movies or TV shows).
///
/// Registered in the centralized `NavigationDestinations` modifier so
/// genre chips on video detail views can push a genre browsing screen
/// using `NavigationLink(value:)`.
struct VideoGenreRoute: Hashable {
    let genre: String
    let libraryId: ItemID?
}
