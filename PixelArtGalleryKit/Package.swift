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
    dependencies: [
        // Sparkle powers in-app updates for the direct-download macOS build.
        // The product is macOS-conditioned below so the iOS app never links it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "PixelArtGalleryKit",
            dependencies: [
                .product(
                    name: "Sparkle",
                    package: "Sparkle",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            resources: [
                .copy("Resources/DefaultSprites"),
            ],
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
