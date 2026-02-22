// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SensorBarHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SensorBarHelper",
            dependencies: ["SensorBarShared"],
            path: "Sources/SensorBarHelper"
        ),
        .target(
            name: "SensorBarShared",
            path: "Sources/Shared"
        ),
    ]
)
