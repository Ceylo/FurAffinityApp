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
        .library(
            name: "FAPages",
            targets: ["FAPages"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/hyperoslo/Cache.git", from: "7.4.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "3.1.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // Android-only: AndroidLogging backs the `os` compatibility module.
        // Matches skip-android-bridge's constraint so both unify on one version.
        .package(url: "https://source.skip.tools/swift-android-native.git", from: "1.4.1"),
    ],
    targets: [
        // Compatibility module: Android has no `os`, so this vends the Logger /
        // OSSignposter surface shared code uses, behind `#if canImport(os)`.
        //
        // It must NOT be named `os`. A module by that name lands in the shared Modules
        // directory and makes `canImport(os)` true for *every* target in the Android
        // build, so whichever target compiles after it takes its Apple branch and
        // fails — Defaults on `AndroidNDK`, swift-android-native's AndroidLogging on
        // `OSLog`, its AndroidSystem on `os_unfair_lock`. Which target breaks is a
        // scheduling race: intermittent in debug, and a hard block in release.
        .target(
            name: "OSCompat",
            dependencies: [
                .product(name: "AndroidLogging", package: "swift-android-native",
                         condition: .when(platforms: [.android])),
            ],
            path: "Sources/OSCompat"
        ),
        .target(
            name: "FALogging",
            dependencies: [
                .target(name: "OSCompat", condition: .when(platforms: [.android])),
            ]
        ),
        .testTarget(
            name: "FALoggingTests",
            dependencies: ["FALogging"]
        ),
        .target(
            name: "FAPages",
            dependencies: [
                "SwiftSoup",
                "FALogging",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .target(name: "OSCompat", condition: .when(platforms: [.android])),
            ]
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
            dependencies: [
                "FAPages",
                "FALogging",
                "SwiftSoup",
                "SwiftGraph",
                .product(name: "OrderedCollections", package: "swift-collections"),
                // Apple-only: Cache backs the CSS/image inliners, ZIPFoundation the
                // DOCX reader — both out of scope on Android.
                .product(name: "Cache", package: "Cache", condition: .when(platforms: [.iOS, .macOS])),
                .product(name: "ZIPFoundation", package: "ZIPFoundation", condition: .when(platforms: [.iOS, .macOS])),
                .target(name: "OSCompat", condition: .when(platforms: [.android])),
            ],
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
