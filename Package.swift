// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bkit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],

    products: [
        .library(
            name: "BkitNetworking",
            targets: ["BkitNetworking"]),
        .library(
            name: "BkitLogging",
            targets: ["BkitLogging"]),
        .library(
            name: "BkitStorage",
            targets: ["BkitStorage"]),
        .library(
            name: "BkitNavigation",
            targets: ["BkitNavigation"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BkitNetworking",
            dependencies: ["BkitLogging"]),
        .target(
            name: "BkitLogging",
            dependencies: []),
        .target(
            name: "BkitStorage",
            dependencies: []),
        .target(
            name: "BkitNavigation",
            dependencies: []),
        .testTarget(
            name: "BkitNetworkingTests",
            dependencies: ["BkitNetworking"]),
        .testTarget(
            name: "BkitNavigationTests",
            dependencies: ["BkitNavigation"]),
    ]
)
