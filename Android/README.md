# FurAffinity on Android (Skip Fuse)

The Android app is built from the same SwiftUI source as the iOS app using
[Skip](https://skip.dev) (Fuse / native mode). The iOS app is unchanged: it is
still built by `FurAffinity.xcodeproj` and none of its files move.

## Layout

```
Package.swift            Skip Fuse app package (Android build only)
Skip.env                 shared app identity (name, version, package)
Android/                 generated Android app shell + Gradle project
Darwin/                  generated iOS bridge project used by `skip` tooling
Project.xcworkspace      workspace `skip` drives
FurAffinityUI/           the Skip target's source directory
  FurAffinityUIRoot.swift  bridged root view + app delegate (Android entry)
  AndroidRootView.swift    placeholder root, replaced screen-by-screen
  Shared/                  SYMLINKS into ../FurAffinity for each ported file
  Skip/skip.yml            marks this a native Skip module
FAKit/                   shared Swift package (cross-compiles, see AGENTS.md)
```

### Why the symlink farm

Skip's transpiler (`skipstone`) walks the **entire** target-directory tree via
its `--project` flag; it honors neither SwiftPM `sources:` nor `exclude:`. So a
target pointed straight at `FurAffinity/` would try to bridge every iOS file and
fail. Instead the Skip target's directory is `FurAffinityUI/`, and each shared
iOS source is pulled in as a **symlink** under `FurAffinityUI/Shared/` as it is
ported. The real files never move (iOS keeps compiling them in place), and the
set of symlinks *is* the allowlist that grows one step at a time.

To add a shared file to the Android build:

```
ln -s ../../FurAffinity/<subpath>/<File>.swift FurAffinityUI/Shared/<File>.swift
```

Keep the link's basename equal to the target's, and preserve subfolders only if
two files share a name.

### Sharing asset-catalog entries

`FurAffinityUI/Resources/Assets.xcassets` is this module's own catalog, which Skip
mirrors into Android resources. To single-source an entry with the iOS catalog,
symlink the **`Contents.json`**, not the `.colorset`/`.imageset` directory:

```
mkdir Foo.colorset
ln -s ../../../../FurAffinity/Assets.xcassets/Foo.colorset/Contents.json Foo.colorset/Contents.json
```

Skip's resource copy does not follow a symlinked *directory* — it silently copies
nothing, and the entry never reaches the APK. The failure is quiet: `Color(_:bundle:)`
falls back to an opaque default, so a 10%-alpha border renders as a solid grey one
instead of erroring. After changing a catalog, confirm the file actually landed:

```
find .build/plugins/outputs/android/FurAffinityUI/destination/skipstone/FurAffinityUI/src/main/assets -type f
```

## Prerequisites

```
skip checkup                 # verifies toolchain (Xcode, Android SDK, Gradle, JDK)
skip android sdk install     # if the Android SDK/NDK is missing
```

## Emulator

Nothing in the Skip toolchain boots an AVD for you. `skip app launch --android`
fails with the emulator reported as **offline** both when no emulator is running
*and* while one is still booting, so boot one first and wait for it:

```
Scripts/start-android-emulator.sh            # boots, waits, never touches the app
skip app launch --android
```

The script is idempotent (a second run just confirms the running device), picks
the only installed AVD unless given a name or `$ANDROID_AVD`, and leaves the
emulator detached so it survives the script exiting or being interrupted. It
takes optional emulator flags: `Scripts/start-android-emulator.sh <avd> -no-window`.

Doing it by hand needs the same two non-obvious parts — detaching the process,
and waiting for `sys.boot_completed` rather than just for adb to see the device:

```
SDK=~/Library/Android/sdk                    # adb/emulator are not on PATH
$SDK/emulator/emulator -list-avds            # e.g. emulator-34-medium_phone
nohup $SDK/emulator/emulator -avd <name> >/tmp/emulator.log 2>&1 &
$SDK/platform-tools/adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
$SDK/platform-tools/adb devices              # must read `device`, not `offline`
```

Troubleshooting:

- **`offline` with the emulator window up** — adb lost the connection:
  `adb kill-server` (it restarts on the next command). The script does this once
  automatically if a device is still offline halfway through its timeout.
- **`emulator -list-avds` is empty** — `skip android sdk install` creates the AVD.
- **AVD hangs on boot** — `adb emu kill`, then relaunch with `-no-snapshot-load`
  to bypass a corrupt quick-boot snapshot.

## Build

```
skip android build           # transpile + compile via SwiftPM (fast inner loop)
skip export                  # release artifacts
```

Transpiled Kotlin lands under `.build/` (e.g.
`.build/plugins/outputs/android/FurAffinityUI/…/skipstone/`). Delete
`.build/plugins/outputs`, `.build/Darwin`, and `.build/Android` after changing
`Skip.env` — the generated Gradle module namespace is cached there.

### Two sources of the Gradle version

`skip gradle` (and the Xcode `Run skip gradle` phase) shells out to the `gradle` on
`PATH` — the Homebrew one — and ignores `gradlew`. Android Studio uses the wrapper,
`Android/gradle/wrapper/gradle-wrapper.properties`. **Keep the two equal** (9.6.1
today); Skip also reads `distributionUrl` out of that file. Skip's catalog pins
AGP 9.2.0 / Kotlin 2.3.0 / compileSdk 36 / JVM 17.

### Why settings.gradle.kts writes local.properties

AGP resolves the Android SDK **per build**, and Skip's transpiled modules are *included*
builds under `.build/` with no `local.properties` of their own — so `Android/local.properties`
does not cover them. `skip gradle` exports `ANDROID_HOME` for the Gradle process it spawns;
Android Studio does not, and its builds failed with `SDK location not found` pointing at
`.build/plugins/outputs/…/skipstone/local.properties`. The `gradle.projectsLoaded` hook at
the end of `Android/settings.gradle.kts` mirrors `sdk.dir` into every included build, after
`includeBuild` and before those projects configure (`settingsEvaluated` is too early —
"Included builds are not yet available for this build"). It rewrites on every sync, since
`.build/` is regularly wiped.

## Run

```
skip app launch --android    # builds the bridge, installs, and launches on the emulator
```

Boot an emulator first (see [Emulator](#emulator)) — this does not start one.

`ANDROID_PACKAGE_NAME` in `Skip.env` **must** equal the Swift module name lowered
to a dotted namespace (`FurAffinityUI` → `fur.affinity.ui`); the generated app
resolves the transpiled module under that group, so a mismatch fails Gradle with
`Could not find <group>:FurAffinityUI:`.

## Debug

```
adb logcat | grep -i fur.affinity           # app logs (tagged fur.affinity.ui.FurAffinityUI)
adb logcat -s FurAffinityUI                  # or filter by tag
```

The **installed app id is `com.example.id1234`**, not `net.furaffinity.spike` — so
`adb shell run-as com.example.id1234 …` is how you reach its data directory (the
image cache lives at `cache/fa_coil_cache`).

Every `skip app launch --android` drops the WebView's Cloudflare clearance, so the
next run shows FA's "Verify you are human" checkbox. It needs a **real click in the
emulator window**: synthetic `adb shell input tap` events do not clear it (that was
the cause of the old "CF loop").

Open `Android/` in Android Studio to attach a debugger to the Kotlin/JNI side (its
`.idea/` is git-ignored; `gradle.xml` there caches paths under `.build/` and is
regenerated on sync — as is `.gradle/config.properties`, whose loss is what makes
Studio warn about an invalid Gradle JDK).
**Never let Studio and `skip`/Xcode build at the same time**: both drive the same Swift
package through `skip android build`, and concurrent invocations fail with
`missing required module 'AndroidNDK'` and `error: cancelled`. Sequentially they are
fine — no wipe needed between drivers.
Swift-side logic runs natively (Skip Fuse), so `PersistentLogger` output appears
in logcat as well — tagged `<subsystem>/<category>`, i.e. `fur.affinity.ui/FA` for
the app module and `FurAffinity/FAKit` / `FurAffinity/FAPages` for FAKit
(`Bundle.main.bundleIdentifier` is nil there, so the subsystem falls back to the
literal `FurAffinity`).

## Test

The parser + logic layer is tested on the emulator via FAKit:

```
cd FAKit && skip android test --testing-library testing
```

The iOS build must stay green at every step:

```
xcodebuild test -scheme FurAffinity -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Forks

| Fork | Why |
|---|---|
| `Ceylo/Defaults` | Android port |
| `Ceylo/Kingfisher` | Android port |
| `Ceylo/skip-ui` | implements `listRowInsets` (upstream: `@available(*, unavailable)`) |
| `Ceylo/skip-fuse-ui` | ditto — the Fuse side of the same modifier |

All on an `android` branch, referenced by URL + branch from `Package.swift` (and,
for Defaults/Kingfisher, the Xcode project too). While iterating, re-point the root
`Package.swift` at a local clone:

```
.package(path: "../../SkipForks/Defaults")     // instead of the URL + branch
```

then push to the `android` branch before the step's gate.

### Why skip-ui / skip-fuse-ui are forked

SkipUI's `List` hardcodes a 16 dp horizontal + 8 dp vertical inset on every row
(`List.contentModifier(level:)`) and `listRowInsets` is unavailable, so rows cannot
go full-bleed. That also silently breaks image prefetching: the row renders 32 dp
narrower than the width the list reports, so `bestThumbnailUrl(for:)` snaps to a
different size bucket and every prefetched thumbnail URL is one no row asks for.

The patch threads an optional `EdgeInsets` through `ListItemModifier` into
`contentModifier`, each edge defaulting to the existing constant, and un-`unavailable`s
`View.listRowInsets` in both repos (skip-ui alone is unreachable from a native Fuse
module). See `SkipSpike/UPSTREAM_INVENTORY.md` §B item 5b for the upstream context.

**Note:** skip-ui arrives transitively via skip-fuse-ui, so overriding it needs its own
entry in `Package.swift`'s `dependencies`, not just the fuse-ui one.

## Images

iOS gets a memory cache, background decoding, request coalescing and a bounded
download queue from Kingfisher. Android has none of that for free, so the pipeline is
three Android-only pieces:

```
FACoilBridge.kt        OkHttp + coil3's standalone DiskCache. Returns an on-disk PATH.
CoilImageLoader.swift  AnyDynamicObject/JNI driver for it.
FAImageStore.swift     memory LRU, coalescing, concurrency gate, off-main decode.
FAImage.swift          KFImage-shaped view + the prefetch API shared views call.
```

Rules that are easy to get wrong here:

- **Nothing decodes on the main actor.** `.task` on a SwiftUI view is MainActor-isolated,
  so anything after an `await` in it resumes on the main thread. Decoding belongs on
  `FAImageStore`'s queue.
- **Never block on a `Task.detached`.** FurAffinityUI is a *native* Skip module, so a
  blocking JNI call there pins a Swift cooperative-pool thread. Go through
  `FAImageStore`'s gate, which submits to a real `DispatchQueue`.
- **No image bytes cross JNI.** The bridge returns a path; `FAImageStore` decodes it.
- **`UIImage(contentsOfFile:)` needs a `file://` URI**, despite the name — SkipUI
  implements it with `Uri.parse` + `ContentResolver.openInputStream`, and a bare
  filesystem path yields nil with no error.
- **The width passed to `prefetchingPreviews` must be the width the row renders at.**
  `bestThumbnailUrl(for:)` snaps to discrete buckets, so a few dp of difference changes
  the URL and silently voids every prefetch. This is what the `listRowInsets` fork is for.
- FA challenges roughly half of all bare image requests (probabilistic, per request), so
  the bridge's retry loop is load-bearing, not defensive padding.

Measured on the emulator before/after this work — cold, disk cache wiped, time for the
first visible thumbnail to appear:

| | before | after |
|---|---|---|
| first visible thumbnail | 4783 ms | 342 ms |
| per-URL network fetch (p50) | 48 ms | 48 ms |
| requests per feed page | 148 | 84 |
| thumbnail prefetches actually used | 0 / 72 | 72 / 72 |

The network was never the problem: the visible rows were queued behind ~144 unbounded
prefetches. Scrolling 72 items and back now serves 93 images from memory vs 38 re-decodes.

## Rules for shared sources

A file under `FurAffinityUI/Shared/` is compiled **twice more** than the iOS target
compiles it: once for Android (`os(Android)` true) and once for the module's Darwin
bridge (`os(Android)` **false**, UIKit importable). Both compiles see only this module —
never the iOS app target — so:

- Guard anything that exists only in the Xcode target (SwiftUI `#Preview`s and their
  demo data) with `#if !FA_SKIP_MODULE`. That flag is defined by `Package.swift` for
  both Skip compiles; `os(Android)` cannot express it.
- Guard Darwin-only frameworks (`Combine`, Kingfisher, Liquid Glass) with
  `#if !os(Android)` / `#if canImport(…)`; those are genuinely per-platform.
- **An Android substitution file must not be `#if os(Android)`-guarded.** When a
  shared file calls one name that resolves per platform (`ImageCacheControl`,
  `clearLoginCookies`, `share`), the Android declaration lives in `FurAffinityUI/`
  while the iOS one stays out of this module. `os(Android)` is false for the Darwin
  bridge compile, so a file-level guard there leaves shared callers with *no*
  declaration at all. Leave the file unguarded and put `#if canImport(Android)`
  around the JNI inside, with a Darwin no-op — the way `CoilImageLoader` does. This
  fails quietly: `skip android build` and the APK are both green, and only
  `skip app launch --android` (which builds the bridge) reports it.
- **`import os` needs no guard.** Android's Swift SDK has no `os` module, so FAKit
  ships one: a target literally named `os` (`FAKit/Sources/OSCompat/`) that re-exports
  `AndroidLogging`'s `Logger` and vends a no-op `OSSignposter`. It is only ever a
  dependency `.when(platforms: [.android])`, so Darwin still resolves the system
  module. Only `Logger` + the `OSSignposter` subset FAKit/FAPages use are covered —
  anything else from `os` (e.g. `OSAllocatedUnfairLock`) still needs a guard, or an
  addition to the shim.
- `#if` blocks must contain balanced braces — split an `if/else` into two whole
  branches rather than fencing one arm.
- `@State`/`@Environment` on a bridged view must be **internal**, not `private`.
- **State property wrappers are matched by attribute name.** skipstone emits a
  bridged view's `Java_initState_<name>`/`Java_syncState_<name>` from the literal
  attribute (`@State`, `@AppStorage`, …). A wrapper of your own gets no entry, so its
  box is never given a Compose state and the value neither persists nor recomposes —
  silently. That is why Android settings toggles are written `@AppStorage(.someKey)`
  (`FurAffinityUI/AndroidAppStorage.swift` adds the `Defaults.Key` initializer) rather
  than behind a re-declared `@Default`; wrapping `AppStorage`, or
  `typealias Default = AppStorage`, does not help. To check, grep the generated
  bridge:

```
grep Java_initState_ .build/plugins/outputs/*/FurAffinityUI/destination/skipstone/SkipBridgeGenerated/<View>_Bridge.swift
```
- SkipUI has no `@Entry` macro: write the `EnvironmentKey` by hand.
- **`CGSize` is fine to use** — but the module has more than one type named `CGSize`
  in scope: `Foundation.CGSize` (which FAKit extends and its APIs take) and the one
  SkipSwiftUI's SwiftUI façade vendors (returned by `GeometryProxy.size` etc.). Rules:
  - As a **type annotation** the bare name `CGSize` is ambiguous — qualify it
    (`Foundation.CGSize`). In an **expression** it usually infers fine from context.
  - A value from a SwiftUI API (`geometry.size`) is the *façade* `CGSize`: it lacks
    FAKit's `maxDimension`/`fitting` and won't pass to `bestThumbnailUrl(for:)`.
    Convert it with `Foundation.CGSize(_:)` from `CGSizeBridge.swift`, exposed on
    `GeometryProxy` as `.faSize`.
  - `import SkipSwiftUI` (needed to *name* the façade type in that bridge initializer)
    makes `GeometryProxy` ambiguous, so keep it in its own file that names no other
    SwiftUI type.

If a build fails with `missing required module 'CJNI'` across unrelated packages, the
incremental state is stale (typically after a `Package.swift` or FAKit change). Wipe it:

```
rm -rf .build/plugins/outputs .build/Darwin .build/Android
```

If that is not enough (it is not, for a FAKit source or manifest change), drop the
SwiftPM build description too — it keeps `.build/checkouts`, so nothing is re-fetched:

```
rm -rf .build/aarch64-unknown-linux-android28 .build/plugins .build/build.db \
       .build/debug.yaml .build/Darwin .build/Android
```
