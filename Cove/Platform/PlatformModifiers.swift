import SwiftUI

// MARK: - Navigation Bar Title Display Mode

/// Centralizes the `#if os(iOS)` guard for `.navigationBarTitleDisplayMode(_:)`
/// so individual views don't need to scatter platform conditionals.
///
/// `.navigationBarTitleDisplayMode` is only available on iOS/iPadOS.
/// On macOS, tvOS, and other platforms these modifiers are no-ops.

extension View {

    /// Sets the navigation bar title display mode to `.inline` on iOS.
    /// No-op on other platforms.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            self.navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    /// Sets the navigation bar title display mode to `.large` on iOS.
    /// No-op on other platforms.
    func largeNavigationTitle() -> some View {
        #if os(iOS)
            self.navigationBarTitleDisplayMode(.large)
        #else
            self
        #endif
    }
}

// MARK: - Text Input Autocapitalization

extension View {

    /// Disables text input autocapitalization on platforms that support it.
    /// No-op on macOS where autocapitalization doesn't apply.
    func disableAutocapitalization() -> some View {
        #if os(iOS) || os(tvOS)
            self.textInputAutocapitalization(.never)
        #else
            self
        #endif
    }
}
