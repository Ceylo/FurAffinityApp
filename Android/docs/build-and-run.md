# Build and run

## Emulator

Nothing in the Skip toolchain boots an AVD for you, and `adb` reports a booting
emulator as **offline** just as it does a missing one. Boot one first and wait for it:

```
Scripts/Android/start-emulator.sh  # boots, waits, never touches the app
Scripts/Android/run.sh
```

The script is idempotent, picks the only installed AVD unless given a name or
`$ANDROID_AVD`, leaves the emulator detached, and passes extra flags through:
`Scripts/Android/start-emulator.sh <avd> -no-window`. By hand, the two non-obvious
parts are detaching the process and waiting for `sys.boot_completed` rather than for
adb to see the device:

```
SDK=~/Library/Android/sdk                    # adb/emulator are not on PATH
nohup $SDK/emulator/emulator -avd <name> >/tmp/emulator.log 2>&1 &
$SDK/platform-tools/adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
```

Troubleshooting:

- **`offline` with the emulator window up**: `adb kill-server`. The script does this
  once by itself if a device is still offline halfway through its timeout.
- **`emulator -list-avds` is empty**: `skip android sdk install` creates the AVD.
- **AVD hangs on boot**: `adb emu kill`, then relaunch with `-no-snapshot-load`.

### Guest RAM

`EMULATOR_MEMORY` (default **4096**) is the guest RAM. Do not lower it: at 3072 the
guest pages ~1.5 GB into zram, lmkd kills continuously, and the app ANRs or
cold-starts instead of resuming. Below 4096 the script passes `-lowram`, the only way
past the emulator's 4096 MB floor (`hw.ramSize` and `-memory` are silently raised;
`hardware-qemu.ini` in the AVD dir says what was used). HVF never hands a dirtied page
back, so a long-running emulator settles around 10 GB of host memory: restart it.

## Build

```
Scripts/Android/run.sh                 # Gradle build, install, start (see Run)
skip android build                     # transpile + compile via SwiftPM, no Darwin bridge
Scripts/Android/build-release-apk.sh   # release APK, see releasing.md
```

Transpiled Kotlin lands under `.build/plugins/outputs/…/skipstone/`, in the worktree
for `skip android build` and in a [build slot](#build-slots) for a Gradle build. Run
`Scripts/Android/clean.sh` after changing `Skip.env`: the generated Gradle module
namespace is cached in both, though a slot also notices the change itself.

### Build cache

`org.gradle.caching` is on, so Gradle's build cache (`~/.gradle/caches/build-cache-1`)
is shared by every worktree and outlives `rm -rf .build`. It holds the Kotlin compiles
of Skip's included builds and the dex merges; the transpiled Kotlin carries no absolute
paths, so one worktree's entries fit another. The Swift side is the [build
slots](#build-slots)' job: `buildAndroidSwiftPackageDebug` and `skip plugin --prebuild`
declare no outputs and always run. `:app:compileDebugKotlin` misses on a new worktree
(its BuildConfig carries the app id suffix), and every `:app` task misses once after a
change to `Android/build-slots/`. `Scripts/Android/prune-build-cache.sh`, run before
each build, caps the cache at 1.5× a clean `.build`. A suspect cached task:
`./gradlew --no-build-cache …`.

### Build slots

A Gradle build — `run.sh`, `debug.sh`, `test.sh`, `./gradlew`, Android Studio —
compiles the Swift side in a **slot**,
`~/Library/Developer/Xcode/DerivedData/android-slot-<n>/`, shared by every worktree,
rather than in the worktree's own `.build`, whose SwiftPM state is keyed by its path.
A new worktree's first build went from 134–235 s to ~18 s.

`Android/settings.gradle.kts` applies `fa.build-slots` (`Android/build-slots/`), which
replaces Skip's settings plugin. Each build leases a slot (`SlotPool.kt`), syncs the
worktree into it (`Scripts/Android/slot-sync.sh`: tracked and untracked-unignored
files, never signing material), prebuilds there and includes the result. The Gradle
root, the `:app` outputs (`.build/Android/app`), the app id suffix and `GIT_COMMIT`
stay the worktree's. The lease is a POSIX lock on `<slot>/.lock`, which `flock(1)`
does not see; probe it with Python's `fcntl.lockf`, as `slots.py` does.

Two measured rules shape the sync:

- **llbuild recompiles on an inode or mtime change alone**, so the copy is
  `rsync -rlp --checksum --no-times`.
- **`/usr/bin/rsync` is openrsync**, which ignored `--delete` and wiped a slot's
  `.build`. So nothing deletes through rsync: `<slot>/.slot-manifest` holds the last
  file list, and a path that leaves it is removed.

What this changes day to day:

- **Errors and DWARF paths name the slot.** Clicking a compiler error in Android Studio
  opens the slot's copy, which the next sync overwrites. Edit the worktree. `debug.sh`
  maps the slot back for LLDB.
- **Generated output is in the slot**: under `$(cat .build/.fa-slot)/.build/`, with
  `android-slot-<n>` as the segment after `outputs/`. Android Studio indexes that Kotlin
  too, so it can show another worktree's code until your next sync.
- **`rm -rf .build` is still a clean build**, in every slot the worktree built in: a
  per-clean token in `.build/.fa-slot-token` tells a slot its copy predates the clean.
  `Scripts/Android/clean.sh` is the same wipe; `--all` also deletes every idle slot.
- **Disk.** A slot is ~3 GB, ~6 GB once a `profile` build ran in it, ~2 GB more once
  `test.sh` did. `FA_ANDROID_SLOTS_MAX` (default 3) bounds the idle ones. A worktree's
  own `.build`, but its `Android/` and `.fa-slot*` files, is then only used by `skip
  android build`, `swift package update` and `build-release-apk.sh`:
  `Scripts/cleanup-worktree.py --orphans` reports it, `--reclaim` deletes it. Xcode's
  "Delete Derived Data" deletes the slots too, which only makes the next build cold.

**Where slots are off**, the base is the worktree: `FA_ANDROID_SLOTS=0` (set by
`build-release-apk.sh`, whose Sentry uploads are path-sensitive), `CI`,
`BUILT_PRODUCTS_DIR` (Xcode's "Run skip gradle" phase), and a relative
`.package(path:)` whose package the slot's copy lacks, such as a [local fork
clone](forks.md) (the build names it; an absolute path, `SKIPLOCAL` included, works).
`skip android build` doesn't go through Gradle, so it never uses a slot. `skip export`
does; release builds go through `build-release-apk.sh` or `FA_ANDROID_SLOTS=0 skip
export`. `FA_ANDROID_SLOTS_DIR` moves the slots' parent directory.

### Two sources of the Gradle version

`skip gradle` (and the Xcode `Run skip gradle` phase) runs the `gradle` on `PATH` and
ignores `gradlew`; Android Studio uses the wrapper. **Keep the two equal**; Skip also
reads `distributionUrl` from `Android/gradle/wrapper/gradle-wrapper.properties`.
Skip's version catalog is generated from skip-unit's `skip.yml`, so the AGP Upgrade
Assistant has nothing of ours to edit: `FurAffinity/Skip/skip.yml` registers
`android-gradle-plugin` ahead of the default (the first registration wins). Bump it
there.

### Why settings.gradle.kts writes local.properties

AGP resolves the Android SDK per build, and Skip's modules are *included* builds under
`.build/` with no `local.properties`. `skip gradle` exports `ANDROID_HOME`; Android
Studio does not, so its builds failed with `SDK location not found`. The
`gradle.projectsLoaded` hook in `Android/settings.gradle.kts` mirrors `sdk.dir` into
every included build (`settingsEvaluated` is too early).

### Known build warnings

A green build still prints ~2000 warning lines, none from this repo's sources. Check
a *new* warning against this list before triaging the log:

- **skip-ui fork**: `UIImage.swift` "unable to match this API call to determine the
  correct actor", `Navigation.swift` "This extension will be moved into its extended
  type definition".
- **Gradle 10 deprecations**: all from skipstone-generated `build.gradle.kts` files
  (`--warning-mode all` names them). None may come from `Android/app/build.gradle.kts`
  or `Android/settings.gradle.kts`, which are ours.
- **"The Kotlin Gradle plugin was loaded multiple times"**: `:FAKit` and `:SkipWeb` are
  Skip's included builds, out of reach.
- **`clang: warning: using sysroot for 'MacOSX' but targeting 'iPhone'`**: the
  `swift build --triple arm64-apple-ios` prebuild linking `.dylib` products.
- **"Detected multiple Kotlin daemon sessions"**: one daemon per worktree.

## Run

```
Scripts/Android/run.sh   # builds, installs, and starts this worktree's app
```

Every worktree installs its **own** debug app: `Android/app/build.gradle.kts` derives
an `applicationIdSuffix` and the launcher label from the worktree directory name, so
branches sit side by side on the one shared AVD. Release is untouched. So don't use
`skip app launch --android`: it reads the unsuffixed app id from `Skip.env`, installs
the suffixed APK and then starts an id that is not there.

`run.sh` builds with `./gradlew :app:installDebug`, whose prebuild also compiles the
**Darwin bridge** (`swift build --triple arm64-apple-ios`, where `os(Android)` is
false) and fails on its errors. That is the build which catches a misplaced
`os(Android)` guard; `skip android build` and `skip android test` never compile it,
so their being green does not mean the app builds. See [shared
sources](shared-sources.md#why-everything-unported-is-guarded). `run.sh` then runs
`check-shared-globals.sh` and holds the emulator lock while it installs.

**A build can fail for reasons that are not your change**, with `missing required
module 'AndroidNDK'`/`'CJNI'` or `no such module 'OSLog'` in an unrelated dependency.
See [Module-name poisoning](#module-name-poisoning) and [Wiping the build
state](#wiping-the-build-state); don't bisect your sources against one such failure.

A related trap with the same signature: a `from:` pin on `skip` drifts past the
installed CLI and the build fails *inside a dependency* (`AndroidUserDefaults` …
"must use a 'required' initializer"). The pin is `exact:` for that reason; keep it
equal to `skip version`.

**Upgrading Skip** moves several things in one commit: `brew upgrade skip`
(machine-wide), the `exact:` pin in `Package.swift`, `FAKit/Package.swift` and
`Ceylo/Kingfisher`, and the upstream merges into the skip-ui / skip-fuse-ui / skip-web
forks, all naming `github.com/skiptools/*` (see [forks.md § One location per
identity](forks.md#one-location-per-identity)). Then `swift package update`, re-resolve
the Xcode project's `Package.resolved`, and build from a clean `.build`. Diff the
generated `SkipBridgeGenerated/*_Bridge.swift` against the previous build: a skipstone
codegen change shows up there first. If the build warns that Skip's
`SkipSettingsPlugin` changed, port the change to `Android/build-slots` and record the
hash it prints in `SKIP_SETTINGS_PLUGIN_SHA256`. The root `Package.resolved` is
committed — see [forks.md](forks.md) for refreshing a fork's pin.

### The shared emulator

There is one AVD for every worktree. Anything that drives it from a second worktree
goes through the lock:

```
Scripts/Android/with-emulator-lock.sh ./gradlew :app:connectedDebugAndroidTest
```

It waits (`--timeout`, default 1800 s), names the holder, and exits with the wrapped
command's status; a lock left by a crashed run clears itself. `run.sh`, `test.sh`,
`debug.sh`, `profile.sh`, `install-apk.sh` and `check-crash-reporting.sh` take it
themselves; wrapping one of them fails at once rather than deadlocking.

### Module-name poisoning

Every target in an Android build shares one Modules directory, so **any** module in it
answers `canImport(<name>)` for **every** target, declared dependency or not. Whether
it is there yet depends on build order, so the failure is intermittent and lands in a
dependency you did not touch. Two instances bit this port, both fixed:

1. **A module named `os`.** Once `os.swiftmodule` existed, `canImport(os)` was true on
   Android and whatever compiled next took its Apple branch (`Defaults` → `missing
   required module 'AndroidNDK'`, `AndroidLogging` → `no such module 'OSLog'`). The
   target is now `OSCompat`.
2. **`canImport(SwiftUI)` in FAKit.** On Android `SwiftUI` is SkipSwiftUI's façade,
   which needs `CJNI`, whose modulemap FAKit's dependency closure lacks. It compiled in
   debug by build-order luck and failed the release build. FAKit gates on `#if
   !os(Android)` now.

The rule: in a plain package, never gate on `canImport` for a module Skip also vends
under that name. Gate on the platform.

`ANDROID_PACKAGE_NAME` in `Skip.env` **must** equal the Swift module name lowered to a
dotted namespace (`FurAffinityUI` → `fur.affinity.ui`), or Gradle fails with `Could not
find <group>:FurAffinityUI:`.

## Debug

```
Scripts/Android/logs.sh                      # our tags only, live (--help for more)
Scripts/Android/logs.sh -d | grep CFFALLBACK # how often the WebView fetch is used
```

`logs.sh` filters by tag rather than pid, so it keeps streaming across an app restart.
Its tags are `<app id>/FA`, `/FAKit`, `/FAPages` (the app id from `Skip.env`, with and
without this worktree's suffix) and each Kotlin bridge's `TAG`, read from
`Android/app/src/main/kotlin/`, so neither drifts. Lines from sibling worktrees' apps
are filtered out by uid.

`[CFFALLBACK]` tags every use of the WebView-fetch fallback, the slow path: one line on
entry, one on rescue, so an entry with no `rescued by WebView` line failed. A healthy
session shows none: challenges are resolved by `CloudflareChallengeCoordinator`, and the
retry goes through the shared OkHttp client.

The **installed app id is `com.example.id1234.<worktree>`** for a debug build, so the
data directory (the image cache is `cache/com.onevcat.Kingfisher.ImageCache.default`)
is `adb shell run-as com.example.id1234.<worktree> …`. `run.sh` prints the id it
starts. A reinstall keeps the container, Cloudflare clearance included; to force a
challenge, see [cloudflare-and-login.md § Forcing a
challenge](cloudflare-and-login.md#forcing-a-challenge). An interactive "Verify you
are human" checkbox needs a **real click in the emulator window**: synthetic `adb shell
input tap` events do not clear it.

The logged-out screen's **"Continue offline (debug)"** and **"Continue offline, empty
(debug)"** buttons drive ported screens without a Cloudflare solve, the latter with no
submissions, notes or notifications. They are gated on `android:debuggable` at
*runtime* (`AndroidAppInfo.isDebuggable`), not `#if DEBUG`, which skipstone drops when
it generates the view bridge; so `OfflineFASession` ships in the release APK, but not
its bundled `Resources/Demo` images, which `app/build.gradle.kts` drops from every
non-debug variant. The
shared `LaunchLog.swift` line says which side of the gate a build is on:

```
Launched FurAffinity 1.19 on Android 17, debug build debuggable=true
```

Swift logging runs natively, so `PersistentLogger` lines reach logcat tagged
`<subsystem>/<category>`. The subsystem is the installed applicationId, set as
`FALogSubsystem.override` from `FurAffinityUIRoot.onInit()`, since
`Bundle.main.bundleIdentifier` is wrong or nil in a Skip module; a process with no
override (the `skip android test` runner) falls back to `FurAffinity`. That one write
reaches every module only because `FALogging` is its own package, linked as one shared
object — see [One module, one image](shared-sources.md#one-module-one-image).

Open `Android/` in Android Studio to debug the Kotlin side. **Never let Studio and
`skip`/Xcode build at the same time**: concurrent builds of the Swift package fail with
`missing required module 'AndroidNDK'` and `error: cancelled`. One after the other is
fine.

### Attaching a Swift debugger

```
Scripts/Android/debug.sh    # build with symbols, install, start lldb-server, write .vscode/
```

Then set a breakpoint in a `.swift` file and press F5 in VS Code (**Swift
(Android)**). Its `preLaunchTask` reruns the script with `--no-build`, so rerun it by
hand only after a build it did not make: `run.sh` installs stripped libraries. The
attach is by process name, so an app restart costs one more F5. What the script
doesn't make obvious:

- **The attach leaves the app paused; press Continue once.** Resuming from
  `postRunCommands` makes lldb-dap abort.
- **Android Studio can debug Kotlin at the same time only as Java/Kotlin only**: its
  native/dual mode takes the ptrace slot LLDB needs.
- **It needs `lldb-dap` from a swift.org toolchain, Swift 6.3+.** Xcode's LLDB lacks
  the Android fixes.
- **A cold attach takes minutes** (~400 modules into `~/.lldb/module_cache`), which is
  why `launch.json` sets `"timeout": 300`; a failure at the 30 s default looks
  intermittent because warm attaches take seconds.
- A session that ends without detaching leaves the app SIGSTOPped; `debug.sh` resumes
  it.

#### Inspecting values

LLDB finds no `Linux.sdk` for the target triple and falls back to the macOS SDK, so
`p` fails with `could not build C module 'Dispatch'` and `po` crashes lldb-dap.
`debug.sh` adds both settings below from the Swift SDK bundle's `swift-sdk.json`:

```
settings set target.sdk-path <bundle>/ndk-sysroot
settings append target.swift-module-search-paths <bundle>/swift-resources/usr/lib/swift-<arch>/android
```

Without the SDK path the ClangImporter hits `#error Unsupported architecture`. The
module path is the `android` directory *below* `swiftResourcesPath`; the parent makes
`CoreFoundation` collide with the host's. swift-foundation's `URL` is pure Swift, so a
`type summary` on a private field shows it as a string; if URLs show blank, use `p
url.absoluteString`. `Data` shows as `slice`; use `p data.count`.

## Test

```
Scripts/Android/test.sh
```

It runs both Android test packages on the running emulator, under [the emulator
lock](#the-shared-emulator), and fails if either reports fewer cases than its floor in
the script, so a run that silently finds no tests cannot pass:

- **FAKit** (FAPages, FAKit, FALogging), from `FAKit/`.
- **FurAffinityUITests** (the root package): the Xcode `FurAffinityTests` directory,
  compiled against `FurAffinityUI` with `FA_SKIP_MODULE` defined; each file picks its
  `@testable import` on that define. The target has no skipstone plugin, so SwiftPM
  honours its `exclude:`.

Left out of the root package:

| iOS-only | Why |
|---|---|
| `LoggedInViewTabTests` | the UIKit tab bar; Android has `AndroidRootView.Tab` |
| `ModelTests` (+ `MockFASession`) | `Model.init` observes `Defaults`, a Kotlin SharedPreferences listener on Android: it needs a JVM, which a native test executable lacks |
| `SettingsMigrationTests.legacyUnmigrated…` | no pre-versioning Android install exists |

`skip android test --apk` would supply the JVM, but its harness crashes on **any**
`@MainActor` test, so `ModelTests` waits on that.

The tests build in a [build slot](#build-slots): `test.sh` hands over to the Gradle
task `faAndroidTest`, which leases and syncs the slot, then runs `test.sh --base
<slot>`. Where slots are off, it builds in the worktree, with no Gradle. Each package
builds in **its own scratch path**, `.build/android-test` and
`.build/android-test-fakit`, because a native build in `.build` itself rewrites the
plugin outputs a Gradle build reads (which then fails with `Unresolved reference
'ProcessInfo'`).

A native test is an `adb shell` process, not an app: it has no `context.cacheDir`, so
the script sets `XDG_CACHE_HOME`. And `UserDefaults` in a test file is SkipAndroidBridge's
JNI-backed store (through `@testable import`); reach the Foundation one `Defaults` uses
as `key.suite`.

### Toolchain vs. Xcode

The Swift toolchain and the Swift Android SDK (installed together by `skip android sdk
install --version X`) must be at least as new as the Swift in the selected Xcode: host
code builds against its macOS SDK. Xcode 27 needs Swift **6.4**; a 6.3 toolchain fails
with `unknown argument: '-target-arch-variant'` or a swift-frontend segfault. Keep only
one `*_android` SDK installed (`swift sdk list`), or `skip android test` finds the
triple ambiguous.

SwiftPM 6.4's `swiftbuild` build system makes the Fuse graph's static-library
duplication a hard error; the Gradle build has run it since skip-bridge 0.18, so every
module of ours sits in exactly one image (see [One module, one
image](shared-sources.md#one-module-one-image)). `test.sh` still passes `--build-system
native`: under swiftbuild, `skip android test` runs only the first test runner it
finds, and FAKit has three.

### CI

`build.yml`'s `Build Android App` job runs beside the iOS one, with no secrets:

1. `Scripts/Android/ci-setup.sh`: swiftly, the skip CLI at the `exact:` pin
   (`check-skip-version.sh --install`), and the Swift Android SDK. Not
   `skiptools/actions/setup-skip`, whose `brew install skip` compiled from source on the
   Intel runner for 20 of its 27 minutes. The toolchain and the SDK (8 GB) are
   downloaded each run: too big to cache usefully.
2. `SKIP_EXPORT_ARCHS=x86_64 ./gradlew :app:assembleDebug`: the build that compiles the
   Darwin bridge and the Kotlin; x86_64 is the emulator's only ABI.
3. `ABI=x86_64 Scripts/Android/check-shared-globals.sh debug`, as `run.sh` does.
4. `Scripts/Android/test.sh` on an API 34 x86_64 emulator, logs uploaded.

It runs on **`macos-26-intel`**: the emulator needs nested virtualisation, which
GitHub's arm64 macOS runners lack. GitHub retires its Intel macOS runners around
**August 2027**. The way off is Linux with KVM for `skip android test`, with step 2 on
arm64 `macos-26` without an emulator, since Skip doesn't support a full app build on
Linux.

The iOS build must stay green at every step:

```
xcodebuild test -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

## Wiping the build state

If a build fails with `missing required module 'CJNI'` across unrelated packages, the
incremental state is stale (typically after a `Package.swift` or FAKit change).
`Scripts/Android/clean.sh` always fixes it, at the price of a cold build. A partial
wipe is quicker but has to reach the slot. `S` is the slot the last Gradle build used,
or the worktree when slots are off; wipe it while no build runs there. These three are
what a `Skip.env` change clears:

```
S="$(cat .build/.fa-slot 2>/dev/null || pwd)"
rm -rf "$S"/.build/{plugins/outputs,Darwin,Android}
```

Under slots the worktree's own `.build/Android` holds the `:app` outputs and stays. If
that is not enough (it is not, for a FAKit source or manifest change), drop the SwiftPM
build description too; `.build/checkouts` stays, so nothing is re-fetched:

```
rm -rf "$S"/.build/{aarch64-unknown-linux-android28,plugins,build.db,debug.yaml,Darwin,Android}
```
