// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bkit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BkitNetworking", targets: ["BkitNetworking"]),
        .library(name: "BkitLogging", targets: ["BkitLogging"]),
        .library(name: "BkitStorage", targets: ["BkitStorage"]),
        .library(name: "BkitNavigation", targets: ["BkitNavigation"]),
    ],
    targets: [
        .target(name: "BkitNetworking"),
        .target(name: "BkitLogging"),
        .target(name: "BkitStorage"),
        .target(name: "BkitNavigation"),
        .testTarget(name: "BkitNetworkingTests", dependencies: ["BkitNetworking"]),
        .testTarget(name: "BkitNavigationTests", dependencies: ["BkitNavigation"]),
    ]
)
