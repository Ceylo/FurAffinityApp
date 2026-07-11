// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FAKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(
            name: "FAKit",
            targets: ["FAKit"]),
        .library(
            name: "FALogging",
            targets: ["FALogging"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/hyperoslo/Cache.git", from: "7.4.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "3.1.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "FALogging"
        ),
        .testTarget(
            name: "FALoggingTests",
            dependencies: ["FALogging"]
        ),
        .target(
            name: "FAPages",
            dependencies: ["SwiftSoup", "FALogging", .product(name: "OrderedCollections", package: "swift-collections")]
        ),
        .testTarget(
            name: "FAPagesTests",
            dependencies: ["FAPages"],
            resources: [
                .copy("data"),
            ]
        ),
        .target(
            name: "FAKit",
            dependencies: ["FAPages", "FALogging", "Cache", "SwiftGraph", .product(name: "OrderedCollections", package: "swift-collections"), "ZIPFoundation"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FAKitTests",
            dependencies: ["FAKit"],
            resources: [
                .copy("data"),
            ]
        ),
    ]
)
