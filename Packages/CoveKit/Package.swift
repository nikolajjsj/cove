// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoveKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "MediaServerKit", targets: ["MediaServerKit"]),
        .library(name: "JellyfinAPI", targets: ["JellyfinAPI"]),
        .library(name: "JellyfinProvider", targets: ["JellyfinProvider"]),
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"]),
        .library(name: "DownloadManager", targets: ["DownloadManager"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "ImageService", targets: ["ImageService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/kean/Nuke", from: "12.0.0"),
    ],
    targets: [
        // MARK: - Source Targets

        .target(
            name: "Models",
            path: "Sources/Models"
        ),
        .target(
            name: "MediaServerKit",
            dependencies: ["Models"],
            path: "Sources/MediaServerKit"
        ),
        .target(
            name: "JellyfinAPI",
            dependencies: ["Models", "Networking"],
            path: "Sources/JellyfinAPI"
        ),
        .target(
            name: "JellyfinProvider",
            dependencies: ["JellyfinAPI", "MediaServerKit", "Networking"],
            path: "Sources/JellyfinProvider"
        ),
        .target(
            name: "PlaybackEngine",
            dependencies: ["Models"],
            path: "Sources/PlaybackEngine"
        ),
        .target(
            name: "DownloadManager",
            dependencies: ["Models", "Persistence", "Networking"],
            path: "Sources/DownloadManager"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Models",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Persistence"
        ),
        .target(
            name: "Networking",
            dependencies: ["Models"],
            path: "Sources/Networking"
        ),
        .target(
            name: "ImageService",
            dependencies: [
                "Models",
                .product(name: "Nuke", package: "Nuke"),
            ],
            path: "Sources/ImageService"
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            path: "Tests/ModelsTests"
        ),
        .testTarget(
            name: "JellyfinAPITests",
            dependencies: ["JellyfinAPI"],
            path: "Tests/JellyfinAPITests"
        ),
        .testTarget(
            name: "JellyfinProviderTests",
            dependencies: ["JellyfinProvider"],
            path: "Tests/JellyfinProviderTests"
        ),
        .testTarget(
            name: "PlaybackEngineTests",
            dependencies: ["PlaybackEngine"],
            path: "Tests/PlaybackEngineTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/PersistenceTests"
        ),
        .testTarget(
            name: "DownloadManagerTests",
            dependencies: ["DownloadManager"],
            path: "Tests/DownloadManagerTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
