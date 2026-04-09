import Foundation
import Models

/// Single source of truth for the App Group identifier shared between the
/// main app and all extensions (widgets, etc.).
///
/// Every place that references the App Group — `UserDefaults(suiteName:)`,
/// `KeychainService(accessGroup:)`, entitlements — should use this constant
/// so a typo in one location can never silently break data sharing.
public enum AppGroupConstants {

    /// The App Group container identifier configured in both the main app
    /// and widget extension entitlements.
    ///
    /// Derived from ``AppConstants/bundleIdentifier`` so the bundle ID
    /// is defined in exactly one place.
    public static let identifier = "group.\(AppConstants.bundleIdentifier)"
}
