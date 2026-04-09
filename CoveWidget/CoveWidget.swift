import SwiftUI
import WidgetKit

struct CoveWidget: Widget {
    let kind = "CoveWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CoveWidgetIntent.self,
            provider: CoveTimelineProvider()
        ) { entry in
            CoveWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Cove")
        .description("Continue Watching or Next Up from your Jellyfin server.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
