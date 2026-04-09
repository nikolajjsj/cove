import Foundation

/// App-wide constants that every module in the project may need.
///
/// Lives in `Models` because it is the universal leaf dependency —
/// every other module already depends on `Models`, so placing these
/// constants here avoids circular-dependency issues that would arise
/// if they lived in a higher-level module like `AppGroup`.
public enum AppConstants {

    /// The app's bundle identifier, used as the base for:
    /// - `Logger` subsystem strings
    /// - Keychain service names
    /// - Background session / dispatch-queue labels
    /// - On-disk directory names
    ///
    /// The App Group identifier in ``AppGroup/AppGroupConstants`` is
    /// derived from this value (`"group.\(bundleIdentifier)"`).
    public static let bundleIdentifier = "com.nikolajjsj.cove"
}
