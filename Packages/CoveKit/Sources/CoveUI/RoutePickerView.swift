#if os(iOS)
    import AVKit
    import SwiftUI

    /// A SwiftUI wrapper around `AVRoutePickerView` that presents the system
    /// audio-output route picker (AirPlay, Bluetooth, etc.).
    ///
    /// Tapping this view opens the system sheet for selecting an audio output device.
    /// Size and tint are controlled via standard SwiftUI modifiers applied to the wrapper.
    public struct RoutePickerView: UIViewRepresentable {
        public init() {}

        public func makeUIView(context: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.prioritizesVideoDevices = false
            picker.tintColor = .secondaryLabel
            picker.activeTintColor = .tintColor
            return picker
        }

        public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
            // No dynamic updates needed
        }
    }
#endif
