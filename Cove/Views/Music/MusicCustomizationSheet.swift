import Defaults
import SwiftUI

/// A sheet that lets users reorder and show/hide music library sections.
///
/// Presented from the `MusicLibraryView` toolbar. Delegates to the generic
/// `SectionCustomizationSheet` for all reorder/toggle behavior.
struct MusicCustomizationSheet: View {
    @Default(.musicSections) private var sections

    var body: some View {
        SectionCustomizationSheet(
            sections: $sections,
            title: "Customize Music"
        )
    }
}
