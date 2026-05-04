import Models

/// Route for navigating to a studio's item listing.
///
/// Registered in `NavigationDestinations` so all navigation goes
/// through `NavigationLink(value:)`.
struct StudioRoute: Hashable {
    let studio: String
    let libraryId: ItemID?
}
