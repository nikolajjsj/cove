import Foundation
import Models
import Nuke
// Re-export NukeUI so consumers only need to import ImageService
@_exported import NukeUI

/// Configures and provides the shared Nuke image pipeline for the app.
public enum ImageService {
    /// The shared image pipeline configured with disk + memory cache.
    public static let pipeline: ImagePipeline = {
        var config = ImagePipeline.Configuration.withDataCache(
            name: "com.nikolajjsj.jellyfin.images",
            sizeLimit: 500 * 1024 * 1024  // 500 MB disk cache
        )
        config.imageCache = ImageCache.shared
        ImageCache.shared.costLimit = 200 * 1024 * 1024  // 200 MB memory cache
        ImageCache.shared.countLimit = 500

        config.isProgressiveDecodingEnabled = true

        return ImagePipeline(configuration: config)
    }()

    /// Call once at app startup to set the shared pipeline.
    public static func configure() {
        ImagePipeline.shared = pipeline
    }
}
