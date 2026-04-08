import Foundation

// MARK: - Navigation Destinations

/// Navigation value for offline series detail.
struct OfflineSeriesDestination: Hashable {
    let seriesId: String
    let serverId: String
    let title: String
}

/// Navigation value for offline album detail.
struct OfflineAlbumDestination: Hashable {
    let albumId: String
    let serverId: String
    let title: String
}
