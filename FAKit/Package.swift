// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FAKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "FAKit",
            targets: ["FAKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.3"),
        .package(url: "https://github.com/sharplet/Regex.git", from: "2.1.1"),
        .package(url: "https://github.com/hyperoslo/Cache.git", from: "6.0.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "3.1.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.4"),
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
            dependencies: ["FAPages", "Cache", "SwiftGraph", .product(name: "OrderedCollections", package: "swift-collections")]),
        .testTarget(
            name: "FAKitTests",
            dependencies: ["FAKit"],
            resources: [
                .copy("data"),
            ]),
    ]
)
