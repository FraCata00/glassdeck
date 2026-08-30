// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GlassDeck",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GlassDeck", targets: ["GlassDeck"]),
        .library(name: "GlassDeckKit", targets: ["GlassDeckKit"]),
    ],
    targets: [
        .target(
            name: "GlassDeckKit",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "GlassDeck",
            dependencies: ["GlassDeckKit"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "GlassDeckKitTests",
            dependencies: ["GlassDeckKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
