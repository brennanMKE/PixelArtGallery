// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PixelArtGalleryKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PixelArtGalleryKit",
            targets: ["PixelArtGalleryKit"]
        ),
    ],
    targets: [
        .target(
            name: "PixelArtGalleryKit",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "PixelArtGalleryKitTests",
            dependencies: ["PixelArtGalleryKit"]
        ),
    ]
)
