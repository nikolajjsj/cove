import WidgetKit

/// The timeline entry that WidgetKit uses to render a snapshot of the widget.
struct CoveWidgetEntry: TimelineEntry {
    let date: Date
    let contentType: WidgetContentType
    let items: [WidgetMediaItem]
    let serverName: String?
}
