import Foundation

/// A lightweight model representing a media item for display in a widget.
///
/// This is intentionally separate from the main app's `MediaItem` to keep
/// the widget extension's dependencies minimal. It contains only the fields
/// needed for widget rendering.
///
/// Images are pre-fetched by the timeline provider and stored as raw `Data`
/// because `AsyncImage` does not work reliably in WidgetKit — widgets are
/// rendered as static snapshots with no live view lifecycle.
struct WidgetMediaItem: Identifiable, Sendable {
    let id: String
    let title: String
    let seriesName: String?
    let seasonEpisodeLabel: String?
    let playbackProgress: Double?
    let imageURL: URL?
    let imageData: Data?

    /// Guaranteed-valid fallback URL used when deep link construction fails.
    // swiftlint:disable:next force_unwrapping
    private static let fallbackURL = URL(string: "cove://")!

    /// Deep link URL that opens this item's detail view in the main app.
    var deepLinkURL: URL {
        URL(string: "cove://item/\(id)") ?? Self.fallbackURL
    }

    /// Deep link URL that resolves this item and starts playback immediately.
    var playURL: URL {
        URL(string: "cove://play/\(id)") ?? Self.fallbackURL
    }
}
