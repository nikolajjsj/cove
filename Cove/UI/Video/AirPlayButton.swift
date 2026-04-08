import AVKit
import SwiftUI

// MARK: - AirPlay Button (iOS)

#if os(iOS)
    struct AirPlayButton: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let routePicker = AVRoutePickerView()
            routePicker.tintColor = .white
            routePicker.activeTintColor = .systemBlue
            routePicker.prioritizesVideoDevices = true
            return routePicker
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }
#endif
