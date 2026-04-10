import Observation
import SwiftUI

/// A single toast notification.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    let style: Style

    /// Visual style for a toast.
    enum Style: Sendable {
        case success
        case error
        case info

        var tint: Color {
            switch self {
            case .success: .green
            case .error: .red
            case .info: .blue
            }
        }
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

/// A centralized, app-wide toast notification manager.
///
/// Use the shared instance to show brief confirmation messages from anywhere:
/// ```swift
/// ToastManager.shared.show("Added to Favorites", icon: "heart.fill")
/// ```
///
/// The manager supports queuing: if a toast is already visible, the new one
/// replaces it with a fresh auto-dismiss timer.
@MainActor
@Observable
final class ToastManager {

    /// The shared singleton instance.
    static let shared = ToastManager()

    /// The currently displayed toast, if any.
    private(set) var currentToast: Toast?

    /// Auto-dismiss task — cancelled when a new toast arrives or manual dismiss.
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a toast with the given message, icon, and optional style.
    ///
    /// - Parameters:
    ///   - message: The text to display.
    ///   - icon: An SF Symbol name (defaults to `"checkmark.circle.fill"`).
    ///   - style: The visual style (`.success`, `.error`, `.info`). Defaults to `.success`.
    ///   - duration: How long to display before auto-dismissing. Defaults to 2.5 seconds.
    func show(
        _ message: String,
        icon: String = "checkmark.circle.fill",
        style: Toast.Style = .success,
        duration: Duration = .seconds(2.5)
    ) {
        // Cancel any pending dismiss
        dismissTask?.cancel()

        // Set the new toast
        currentToast = Toast(message: message, icon: icon, style: style)

        // Schedule auto-dismiss
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Dismiss the current toast immediately.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        currentToast = nil
    }
}
