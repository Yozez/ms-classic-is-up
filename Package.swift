// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MSClassicIsUp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MSClassicTray", targets: ["MSClassicTray"]),
        .library(name: "MSClassicCore", targets: ["MSClassicCore"]),
    ],
    targets: [
        .target(name: "MSClassicCore"),
        .executableTarget(
            name: "MSClassicTray",
            dependencies: ["MSClassicCore"]
        ),
        .testTarget(
            name: "MSClassicCoreTests",
            dependencies: ["MSClassicCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
