import Foundation

// MARK: - Navigation Destinations

/// Navigation value for offline series detail.
struct OfflineSeriesDestination: Hashable {
    let seriesId: String
    let serverId: String
    let title: String
}

