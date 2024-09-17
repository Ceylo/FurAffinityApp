// swift-tools-version:6.0
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
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/hyperoslo/Cache.git", from: "7.4.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "3.1.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
    ],
    targets: [
        .target(
            name: "FAPages",
            dependencies: ["SwiftSoup"]
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
            dependencies: ["FAPages", "Cache", "SwiftGraph", .product(name: "OrderedCollections", package: "swift-collections")],
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
