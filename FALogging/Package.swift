// swift-tools-version:6.0
// The logging package.
//
// Its tests live in FAKit (`FAKit/Tests/FALoggingTests`), not here: the Xcode
// project can only reach test targets through a package it has a *folder*
// reference for, and FALogging must instead be an XCLocalSwiftPackageReference
// to be a workspace root at all — see Android/docs/shared-sources.md
// § One module, one image.
//
// FALogging lives outside FAKit so that FAKit and FAPages reach it as a
// *cross-package product*, which SwiftPM links dynamically. A target
// dependency inside one package is linked statically into each consuming
// product instead, which gave the Android build three copies of every
// FALogging global — see Android/docs/shared-sources.md § One module, one image.

import PackageDescription

let package = Package(
    name: "FALogging",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(
            name: "FALogging",
            targets: ["FALogging"]),
        .library(
            name: "OSCompat",
            targets: ["OSCompat"]),
    ],
    dependencies: [
        // Android-only: AndroidLogging backs the `os` compatibility module.
        // Matches skip-android-bridge's constraint so both unify on one version.
        .package(url: "https://source.skip.tools/swift-android-native.git", from: "1.4.1"),
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
    ]
)

// Android build only. Unset in Xcode and in the Darwin bridge pass.
if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    // Dynamic, or a consumer links this statically and gets its own copy of
    // FALogSubsystem.override and PersistentLogStore.shared — see
    // Android/docs/shared-sources.md § One module, one image.
    package.products = package.products.map { product in
        guard let library = product as? Product.Library else { return product }
        return .library(name: library.name, type: .dynamic, targets: library.targets)
    }
}
