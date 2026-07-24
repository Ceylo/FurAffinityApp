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

Open `Android/` in Android Studio to attach a debugger to the Kotlin/JNI side.
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

## Forks (later steps)

`Defaults` and `Kingfisher` are ported to Android on `Ceylo/<repo>` `android`
branches, referenced by URL + branch from both `Package.swift` and the Xcode
project. While iterating, re-point the root `Package.swift` at a local clone:

```
.package(path: "../SkipForks/Defaults")     // instead of the URL + branch
```

then push to the `android` branch before the step's gate.

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
