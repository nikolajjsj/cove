import Defaults
import Foundation

/// A protocol for section identifiers that support user-configurable ordering and visibility.
///
/// Conform your section enum to this protocol and pair it with `SectionConfig`
/// to enable drag-to-reorder and show/hide functionality using
/// `SectionCustomizationSheet`.
protocol ConfigurableSection: RawRepresentable<String>, CaseIterable, Codable, Hashable, Sendable, Defaults.Serializable {
    /// Human-readable name shown in the customization sheet.
    var displayName: String { get }

    /// SF Symbol used in the customization sheet row.
    var systemImage: String { get }

    /// The default section order and visibility for first launch or reset.
    static var defaultConfigurations: [SectionConfig<Self>] { get }
}

/// A single entry in a user-ordered section list.
///
/// Each entry pairs a `ConfigurableSection` identifier with a visibility toggle.
/// Persist an array of these to let users customize which sections appear and in what order.
struct SectionConfig<Section: ConfigurableSection>: Codable, Equatable, Sendable, Defaults.Serializable {
    /// Which section this entry represents.
    let section: Section

    /// Whether the section is currently visible.
    var isVisible: Bool
}

extension Array {
    /// Inserts sections from the default list that are missing from this array.
    ///
    /// Each missing section is inserted at the relative position it holds in the
    /// defaults, preserving the existing order and visibility for everything else.
    mutating func migrateMissingSections<S: ConfigurableSection>() where Element == SectionConfig<S> {
        let defaults = S.defaultConfigurations
        let existing = map(\.section)
        let missing = defaults.filter { !existing.contains($0.section) }
        guard !missing.isEmpty else { return }

        for config in missing {
            guard let defaultIndex = defaults.firstIndex(where: { $0.section == config.section }) else {
                append(config)
                continue
            }

            let precedingDefaults = defaults[..<defaultIndex].map(\.section)
            if let insertAfter = lastIndex(where: { precedingDefaults.contains($0.section) }) {
                insert(config, at: index(after: insertAfter))
            } else {
                insert(config, at: startIndex)
            }
        }
    }
}
