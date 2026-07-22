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

An emulator (AVD) must be booted before launching:

```
~/Library/Android/sdk/emulator/emulator -list-avds
~/Library/Android/sdk/emulator/emulator -avd <name> &
~/Library/Android/sdk/platform-tools/adb devices     # wait for `device`
```

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
in logcat as well.

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
