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
        // FAKit is a skipstone bridging module so it can own the Android web layer —
        // see Android/docs/shared-sources.md. Keep `skip` equal to the root manifest's.
        .package(url: "https://source.skip.tools/skip.git", exact: "1.9.4"),
        .package(url: "https://github.com/Ceylo/skip-fuse-ui.git", branch: "android"),
        .package(url: "https://github.com/Ceylo/skip-ui.git", branch: "android"),
        .package(url: "https://source.skip.tools/skip-web.git", from: "0.11.2"),
    ],
    targets: [
        // Compatibility module: Android has no `os`, so this vends the Logger /
        // OSSignposter surface shared code uses, behind `#if canImport(os)`. Its name
        // matters — see Sources/OSCompat/OSCompat.swift.
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
                // Unconditional on purpose: SKIP_BRIDGE is unset in the pass that runs
                // plugins, so gating either edge makes skipstone emit a stub
                // build.gradle.kts and Gradle dies on "Unresolved reference 'android'".
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SkipWeb", package: "skip-web"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
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

// Android build only. Unset in Xcode and in the Darwin bridge pass, so neither sees
// FA_SKIP_MODULE — the plugin above must stay outside this block.
if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    for target in package.targets where target.name == "FAKit" {
        target.swiftSettings = (target.swiftSettings ?? []) + [.define("FA_SKIP_MODULE")]
    }
    // all library types must be dynamic to support bridging
    package.products = package.products.map { product in
        guard let library = product as? Product.Library else { return product }
        return .library(name: library.name, type: .dynamic, targets: library.targets)
    }
}
