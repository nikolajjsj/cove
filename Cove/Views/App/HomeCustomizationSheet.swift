import Defaults
import SwiftUI

/// A sheet that lets users reorder and show/hide home screen sections.
///
/// Presented from the ``HomeView`` toolbar. Each row displays the section
/// name with a toggle for visibility, and drag handles allow reordering.
struct HomeCustomizationSheet: View {
    @Default(.homeSections) private var sections
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.section) { config in
                    HomeSectionRow(
                        config: config,
                        onToggle: { toggleVisibility(for: config.section) }
                    )
                }
                .onMove { source, destination in
                    sections.move(fromOffsets: source, toOffset: destination)
                }

                Section {
                    Button("Reset to Default", role: .destructive) {
                        sections = HomeSectionConfig.defaultSections
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home")
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

    private func toggleVisibility(for section: HomeSection) {
        guard let index = sections.firstIndex(where: { $0.section == section }) else { return }
        sections[index].isVisible.toggle()
    }
}

// MARK: - Row View

private struct HomeSectionRow: View {
    let config: HomeSectionConfig
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
