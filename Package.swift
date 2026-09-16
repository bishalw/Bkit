// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bkit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    
    products: [
        .library(
            name: "Bkit",
            targets: ["Bkit"]),
        .library(
            name: "BkitNavigation",
            targets: ["BkitNavigation"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Bkit",
            dependencies: []),
        .target(
            name: "BkitNavigation",
            dependencies: []),
        .testTarget(
            name: "BkitTests",
            dependencies: ["Bkit"]),
        .testTarget(
            name: "BkitNavigationTests",
            dependencies: ["BkitNavigation"]),
    ]
)
