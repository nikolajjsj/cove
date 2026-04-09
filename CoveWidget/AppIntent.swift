import AppIntents
import WidgetKit

enum WidgetContentType: String, AppEnum {
    case continueWatching
    case nextUp

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Content Type"
    }

    static var caseDisplayRepresentations: [WidgetContentType: DisplayRepresentation] {
        [
            .continueWatching: "Continue Watching",
            .nextUp: "Next Up",
        ]
    }
}

struct CoveWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Cove Widget"
    static var description: IntentDescription = "Choose what to display in your Cove widget."

    @Parameter(title: "Content", default: .continueWatching)
    var contentType: WidgetContentType
}
