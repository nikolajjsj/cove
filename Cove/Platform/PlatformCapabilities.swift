import SwiftUI

/// Describes which features the current platform supports.
///
/// Injected via `@Environment(\.platformCapabilities)` so views can adapt
/// at runtime without scattering `#if os()` checks throughout the codebase.
///
/// Compile-time platform differences (e.g. entirely different view types like
/// `AirPlayButton` or `VideoGestureLayer`) still use `#if os()`, but feature
/// flags — like whether to show the downloads tab — use this instead.
///
/// ## Usage
/// ```swift
/// struct SettingsView: View {
///     @Environment(\.platformCapabilities) private var capabilities
///
///     var body: some View {
///         if capabilities.supportsOrientationLock {
///             Toggle("Force landscape", isOn: $forceLandscape)
///         }
///     }
/// }
/// ```
struct PlatformCapabilities: Sendable {

    // MARK: - Feature Flags

    /// Whether offline downloads are supported on this platform.
    var supportsDownloads: Bool

    /// Whether Picture-in-Picture video playback is available.
    var supportsPiP: Bool

    /// Whether the device supports forced orientation lock (e.g. landscape video).
    var supportsOrientationLock: Bool

    // MARK: - Platform Defaults

    /// The resolved capabilities for the current platform at compile time.
    static var current: PlatformCapabilities {
        #if os(iOS)
            PlatformCapabilities(
                supportsDownloads: true,
                supportsPiP: true,
                supportsOrientationLock: true
            )
        #elseif os(tvOS)
            PlatformCapabilities(
                supportsDownloads: false,
                supportsPiP: false,
                supportsOrientationLock: false
            )
        #elseif os(macOS)
            PlatformCapabilities(
                supportsDownloads: true,
                supportsPiP: false,
                supportsOrientationLock: false
            )
        #elseif os(watchOS)
            PlatformCapabilities(
                supportsDownloads: false,
                supportsPiP: false,
                supportsOrientationLock: false
            )
        #elseif os(visionOS)
            PlatformCapabilities(
                supportsDownloads: true,
                supportsPiP: false,
                supportsOrientationLock: false
            )
        #endif
    }
}

// MARK: - Environment Key

private struct PlatformCapabilitiesKey: EnvironmentKey {
    static let defaultValue = PlatformCapabilities.current
}

extension EnvironmentValues {
    /// The platform capabilities for the current environment.
    ///
    /// Defaults to ``PlatformCapabilities/current`` (resolved at compile time).
    /// Can be overridden in previews or tests to simulate other platforms.
    var platformCapabilities: PlatformCapabilities {
        get { self[PlatformCapabilitiesKey.self] }
        set { self[PlatformCapabilitiesKey.self] = newValue }
    }
}
