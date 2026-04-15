import SwiftUI

/// A chip that cycles through All / Watched / Unwatched filter states.
struct WatchedFilterChip: View {
    @Binding var selection: WatchedFilter

    var body: some View {
        Menu {
            Picker("Status", selection: $selection) {
                ForEach(WatchedFilter.allCases, id: \.self) { filter in
                    Label(filter.label, systemImage: filter.systemImage).tag(filter)
                }
            }
        } label: {
            Label(
                selection == .all ? "Watched" : selection.label,
                systemImage: selection.systemImage
            )
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(selection != .all ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
    }
}
