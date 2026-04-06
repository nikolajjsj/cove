import SwiftUI

/// A brief confirmation toast that slides up from the bottom of the screen.
///
/// Place this as an overlay in the app shell. It auto-dismisses after 2 seconds.
struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        if isVisible {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toast.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible = false
        }
        // Give animation time to complete before removing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }

    private func appear() {
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            isVisible = true
        }

        #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        #endif

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if isVisible {
                dismiss()
            }
        }
    }
}

// MARK: - View Modifier for Easy Overlay

extension View {
    /// Overlays a toast notification at the bottom of the view.
    func toastOverlay(toast: Binding<ToastMessage?>) -> some View {
        self.overlay(alignment: .bottom) {
            if let currentToast = toast.wrappedValue {
                ToastView(toast: currentToast) {
                    toast.wrappedValue = nil
                }
                .padding(.bottom, 80)  // Above the Now Playing bar / tab bar
                .id(currentToast.id)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: toast.wrappedValue?.id)
    }
}
