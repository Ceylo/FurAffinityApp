// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FAKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(
            name: "FAKit",
            targets: ["FAKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.3"),
        .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.1"),
    ],
    targets: [
        .target(
            name: "FAPages",
            dependencies: ["SwiftSoup", "Regex"]),
        .testTarget(
            name: "FAPagesTests",
            dependencies: ["FAPages"],
            resources: [
                .copy("data"),
            ]),
        .target(
            name: "FAKit",
            dependencies: ["FAPages"]),
        .testTarget(
            name: "FAKitTests",
            dependencies: ["FAKit"],
            resources: [
                .copy("data"),
            ]),
    ]
)
