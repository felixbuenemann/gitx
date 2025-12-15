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
    dependencies: [
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX", from: "0.2.0"),
        .package(url: "https://github.com/appstefan/highlightswift.git", from: "1.1.0")
    ],
    targets: [
        // Core library with Git functionality
        .target(
            name: "GitXCore",
            dependencies: [
                .product(name: "SwiftGitX", package: "SwiftGitX"),
                .product(name: "HighlightSwift", package: "highlightswift")
            ],
            path: "Sources",
            exclude: ["CLI"],
            sources: [
                "App",
                "Utilities",
                "Views"
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
