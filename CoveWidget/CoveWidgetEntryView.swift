import SwiftUI
import WidgetKit

/// The root view for a Cove widget entry, delegating to the appropriate
/// size-specific view based on the current widget family.
struct CoveWidgetEntryView: View {
    let entry: CoveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            WidgetEmptyStateView(serverName: entry.serverName)
        } else {
            switch family {
            case .systemSmall:
                if let item = entry.items.first {
                    SmallWidgetView(item: item)
                }
            case .systemMedium:
                MediumWidgetView(items: entry.items)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                MediumWidgetView(items: entry.items)
            }
        }
    }
}
