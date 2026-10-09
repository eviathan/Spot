// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpotCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpotCore", targets: ["SpotCore"]),
    ],
    targets: [
        .target(
            name: "SpotCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpotCoreTests",
            dependencies: ["SpotCore"]
        ),
    ]
)
