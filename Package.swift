// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bkit",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15)
    ],
    
    products: [
        .library(
            name: "Bkit",
            targets: ["Bkit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Bkit",
            dependencies: []),
        .testTarget(
            name: "BkitTests",
            dependencies: ["Bkit"]),
    ]
)

