// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FAPages",
    products: [
        .library(
            name: "FAPages",
            targets: ["FAPages"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.3"),
    ],
    targets: [
        .target(
            name: "FAPages",
            dependencies: ["SwiftSoup"]),
        .testTarget(
            name: "FAPagesTests",
            dependencies: ["FAPages"],
            resources: [
                .copy("Resources"),
            ]),
    ]
)
