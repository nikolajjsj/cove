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
    // `let`, not `var`: these never change, and as mutable statics they are
    // global shared mutable state that Swift 6 rejects.
    static let title: LocalizedStringResource = "Cove Widget"
    static let description = IntentDescription("Choose what to display in your Cove widget.")

    @Parameter(title: "Content", default: .continueWatching)
    var contentType: WidgetContentType
}
