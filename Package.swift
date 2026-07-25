// swift-tools-version: 6.1
// The Skip (https://skip.dev) app package for the Android build.
//
// The iOS app is built by FurAffinity.xcodeproj and is unaffected by this
// manifest.
//
// The FurAffinityUI target's directory holds the Android-only entry point plus a
// `Shared/` folder of *symlinks* into ../FurAffinity for each shared source as it
// is ported. Skip's transpiler walks the whole target directory (it honors
// neither SwiftPM `sources:` nor `exclude:`), so the allowlist has to be the set
// of files physically present under this directory — the symlinks are that
// allowlist. The real files never move and the iOS Xcode target is untouched.
import PackageDescription

let package = Package(
    name: "FurAffinityApp",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FurAffinityUI", type: .dynamic, targets: ["FurAffinityUI"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.4"),
        // Forked for `listRowInsets` (unavailable upstream in both repos) — see
        // Android/README.md §Forks. skip-ui comes in transitively via skip-fuse-ui,
        // so it must be overridden here too.
        .package(path: "../../SkipForks/skip-fuse-ui"),
        .package(path: "../../SkipForks/skip-ui"),
        .package(url: "https://source.skip.tools/skip-web.git", from: "0.11.2"),
        .package(path: "FAKit"),
        .package(url: "https://github.com/Ceylo/Defaults.git", branch: "android"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/mxcl/Version.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "FurAffinityUI",
            dependencies: [
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SkipWeb", package: "skip-web"),
                .product(name: "FAKit", package: "FAKit"),
                .product(name: "FALogging", package: "FAKit"),
                .product(name: "FAPages", package: "FAKit"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Version", package: "Version"),
            ],
            path: "FurAffinityUI",
            // Skip mirrors the catalog's imagesets/colorsets into Android resources.
            resources: [.process("Resources")],
            // Marks a compile of *this* module — Android and its Darwin bridge alike.
            // Shared sources use `#if !FA_SKIP_MODULE` to keep bits that only exist in
            // the iOS Xcode target (SwiftUI previews and their demo data) out of it.
            // `os(Android)` can't do that job: the Darwin bridge compile of this module
            // is not Android.
            swiftSettings: [.define("FA_SKIP_MODULE")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
