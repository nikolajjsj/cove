import Defaults
import SwiftUI

/// A reusable sheet that lets users reorder and show/hide sections.
///
/// Pass a binding to the persisted section array and a title.
/// Each row shows the section display name and icon with a visibility toggle,
/// and drag handles allow reordering.
struct SectionCustomizationSheet<S: ConfigurableSection>: View {
    @Binding var sections: [SectionConfig<S>]
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.section) { config in
                    SectionConfigRow(
                        config: config,
                        onToggle: { toggleVisibility(for: config.section) }
                    )
                }
                .onMove { source, destination in
                    sections.move(fromOffsets: source, toOffset: destination)
                }

                Section {
                    Button("Reset to Default", role: .destructive) {
                        sections = S.defaultConfigurations
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleVisibility(for section: S) {
        guard let index = sections.firstIndex(where: { $0.section == section }) else { return }
        sections[index].isVisible.toggle()
    }
}

// MARK: - Row View

private struct SectionConfigRow<S: ConfigurableSection>: View {
    let config: SectionConfig<S>
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Label(config.section.displayName, systemImage: config.section.systemImage)

            Spacer()

            Toggle(
                config.section.displayName,
                isOn: Binding(
                    get: { config.isVisible },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
        }
    }
}
