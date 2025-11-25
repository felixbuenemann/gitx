// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GitX",
            targets: ["GitX"]
        ),
        .library(
            name: "GitXCore",
            targets: ["GitXCore"]
        )
    ],
    dependencies: [
        // Add any Swift package dependencies here
    ],
    targets: [
        // Main application target
        .executableTarget(
            name: "GitX",
            dependencies: ["GitXCore"],
            path: "Sources/App",
            exclude: [],
            resources: [
                .process("../Resources")
            ]
        ),
        // Core library with Git functionality
        .target(
            name: "GitXCore",
            dependencies: [],
            path: "Sources",
            exclude: ["App"],
            sources: [
                "Git",
                "Utilities",
                "Views",
                "Controllers"
            ]
        ),
        // Tests
        .testTarget(
            name: "GitXTests",
            dependencies: ["GitXCore"],
            path: "Tests"
        )
    ]
)
