import SwiftUI

/// A chip for filtering by decade of release.
struct DecadeChip: View {
    @Binding var selection: Decade?

    var body: some View {
        Menu {
            Picker("Year", selection: $selection) {
                Text("Any Year").tag(Decade?.none)
                ForEach(Decade.allCases, id: \.self) { decade in
                    Text(decade.rawValue).tag(Decade?.some(decade))
                }
            }
        } label: {
            Label(selection?.rawValue ?? "Year", systemImage: "calendar")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selection != nil ? .accentColor : .secondary)
        .buttonBorderShape(.capsule)
    }
}
