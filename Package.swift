// swift-tools-version: 6.1
// The Skip (https://skip.dev) app package for the Android build.
//
// The iOS app is built by FurAffinity.xcodeproj and is unaffected by this
// manifest.
//
// The Android target compiles the *same* directory as the iOS app: `FurAffinity/`.
// Skip's transpiler walks that whole tree (it honors neither SwiftPM `sources:`
// nor `exclude:`), so every source it finds must either build for Android or be
// guarded out with `#if !FA_SKIP_MODULE` — see below and AGENTS.md §Working Notes.
// The module keeps the name FurAffinityUI: it is what ANDROID_PACKAGE_NAME and
// Skip.env's PRODUCT_NAME are derived from.
import PackageDescription

let package = Package(
    name: "FurAffinityApp",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FurAffinityUI", type: .dynamic, targets: ["FurAffinityUI"]),
    ],
    dependencies: [
        // Exact, not `from:`: a floating pin silently drifts past the installed
        // `skip` CLI and the build fails inside a dependency (`AndroidUserDefaults`
        // … "must use a 'required' initializer"). Keep this equal to `skip version`.
        .package(url: "https://github.com/skiptools/skip.git", exact: "1.9.11"),
        // Forked for `listRowInsets`, `Text(AttributedString)`, `FlowRow` and a few
        // unavailable-to-passthrough fixes — see Android/docs/forks.md. skip-web is
        // forked for its dependency locations alone. One location per package
        // identity: the forks name Ceylo/skip-ui between them, so this manifest must
        // not re-declare it.
        .package(url: "https://github.com/Ceylo/skip-fuse-ui.git", branch: "android"),
        .package(url: "https://github.com/Ceylo/skip-web.git", branch: "android"),
        // Forked to build on Android: platform guards plus a decode seam onto
        // SkipSwiftUI's `UIImage`, and a bridgeable SwiftUI layer — see
        // Android/docs/forks.md.
        .package(url: "https://github.com/Ceylo/Kingfisher.git", branch: "android"),
        .package(path: "FAKit"),
        .package(path: "FALogging"),
        .package(url: "https://github.com/Ceylo/Defaults.git", branch: "android"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/mxcl/Version.git", from: "2.0.0"),
        // Unused here: pins skip-fuse-ui's Android-only `#Preview` macro dependency, which a
        // Darwin `swift package update` would otherwise prune. Keep the range equal to the fork's.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0"),
    ],
    targets: [
        .target(
            name: "FurAffinityUI",
            dependencies: [
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SkipWeb", package: "skip-web"),
                .product(name: "FAKit", package: "FAKit"),
                .product(name: "FALogging", package: "FALogging"),
                .product(name: "FAPages", package: "FAKit"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Version", package: "Version"),
            ],
            path: "FurAffinity",
            // iOS-target-only artifacts. `exclude:` is honored by SwiftPM (it is
            // *skipstone* that ignores it), and skipstone only ever globs `.swift`
            // plus `Resources/` by name, so excluding non-Swift paths is safe — and
            // necessary: Assets.xcassets would otherwise collide with the catalog
            // below as a second resource of the same name.
            exclude: [
                "Assets.xcassets",
                "iOS/Info.plist",
                "iOS/FurAffinity.entitlements",
                "iOS/AppIconLG.icon",
                "iOS/AppIconLG-debug.icon",
                "iOS/Preview Content",
            ],
            // Skip mirrors the catalog's imagesets/colorsets into Android resources.
            resources: [.process("Resources")],
            // Marks a compile of *this* module — the Android cross-compile and the
            // host build alike. Everything the Android build does not compile carries
            // `#if !FA_SKIP_MODULE`: unported screens and iOS-only files.
            // `os(Android)` cannot do that job — it is false for the host build, which
            // would then have to resolve UIKit, Kingfisher and friends.
            swiftSettings: [.define("FA_SKIP_MODULE")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
