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
            dependencies: ["CStretch"],
            resources: [.process("Resources")]
        ),
        // Signalsmith Stretch (time-stretching), vendored headers behind a C interface
        .target(
            name: "CStretch",
            exclude: [
                "vendor/README.md",
                "vendor/signalsmith-stretch/LICENSE.txt",
                "vendor/signalsmith-linear/LICENSE.txt",
            ],
            cxxSettings: [
                .headerSearchPath("vendor"),
                .define("SIGNALSMITH_USE_ACCELERATE"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
            ]
        ),
        .testTarget(
            name: "SpotCoreTests",
            dependencies: ["SpotCore"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
