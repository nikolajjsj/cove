import SwiftUI

/// Renders the current toast from ``ToastManager`` as a floating capsule
/// at the bottom of the screen.
///
/// Apply this once near the root of the view hierarchy:
/// ```swift
/// RootView()
///     .toastOverlay()
/// ```
struct ToastOverlayView: View {
    @State private var toastManager = ToastManager.shared

    var body: some View {
        Group {
            if let toast = toastManager.currentToast {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        toastManager.dismiss()
                    }
                } label: {
                    toastCapsule(toast)
                }
                .buttonStyle(.plain)
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: toastManager.currentToast?.id)
    }

    private func toastCapsule(_ toast: Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(toast.style.tint)

            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .sensoryFeedback(.success, trigger: toast.id)
    }
}

// MARK: - View Modifier

extension View {
    /// Overlays toast notifications at the bottom of the view.
    ///
    /// Apply once near the root (e.g. on `RootView`). Toasts are shown
    /// by calling ``ToastManager/shared``.
    func toastOverlay() -> some View {
        self.overlay(alignment: .bottom) {
            ToastOverlayView()
                .padding(.bottom, 100)
        }
    }
}
