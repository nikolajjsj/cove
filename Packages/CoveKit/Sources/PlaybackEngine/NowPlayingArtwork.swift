import Foundation
import MediaPlayer

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if canImport(UIKit)
    /// The platform's bitmap image type.
    typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    /// The platform's bitmap image type.
    typealias PlatformImage = NSImage
#endif

extension MPMediaItemArtwork {
    /// Builds now-playing artwork from decoded image data.
    ///
    /// `MPMediaItemArtwork(image:)` is iOS/tvOS-only, which broke the macOS build
    /// of this package (and with it `swift test`). `init(boundsSize:requestHandler:)`
    /// exists on every platform and is the API Apple documents, so it is used here
    /// for all of them.
    static func make(from data: Data) -> MPMediaItemArtwork? {
        guard let image = PlatformImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
