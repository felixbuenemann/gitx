// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GitXCore",
            targets: ["GitXCore"]
        )
    ],
    dependencies: [],
    targets: [
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
