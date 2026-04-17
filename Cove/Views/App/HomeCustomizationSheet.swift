import Defaults
import SwiftUI

/// A sheet that lets users reorder and show/hide home screen sections.
///
/// Presented from the `HomeView` toolbar. Delegates to the generic
/// `SectionCustomizationSheet` for all reorder/toggle behavior.
struct HomeCustomizationSheet: View {
    @Default(.homeSections) private var sections

    var body: some View {
        SectionCustomizationSheet(
            sections: $sections,
            title: "Customize Home"
        )
    }
}
