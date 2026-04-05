import AVFoundation
import SwiftUI

#if os(iOS)
    import UIKit

    struct VideoRenderView: UIViewRepresentable {
        let player: AVPlayer

        func makeUIView(context: Context) -> PlayerUIView {
            let view = PlayerUIView()
            view.player = player
            view.backgroundColor = .black
            return view
        }

        func updateUIView(_ uiView: PlayerUIView, context: Context) {
            if uiView.player !== player {
                uiView.player = player
            }
        }

        final class PlayerUIView: UIView {
            override static var layerClass: AnyClass { AVPlayerLayer.self }

            var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

            var player: AVPlayer? {
                get { playerLayer.player }
                set {
                    playerLayer.player = newValue
                    playerLayer.videoGravity = .resizeAspect
                }
            }
        }
    }

#elseif os(macOS)
    import AppKit

    struct VideoRenderView: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> PlayerNSView {
            let view = PlayerNSView(player: player)
            return view
        }

        func updateNSView(_ nsView: PlayerNSView, context: Context) {
            if nsView.playerLayer.player !== player {
                nsView.playerLayer.player = player
            }
        }

        final class PlayerNSView: NSView {
            let playerLayer: AVPlayerLayer

            init(player: AVPlayer) {
                self.playerLayer = AVPlayerLayer(player: player)
                super.init(frame: .zero)

                wantsLayer = true
                playerLayer.videoGravity = .resizeAspect
                playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer?.addSublayer(playerLayer)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func layout() {
                super.layout()
                playerLayer.frame = bounds
            }
        }
    }
#endif
