# Build and run

## Emulator

Nothing in the Skip toolchain boots an AVD for you. `skip app launch --android`
fails with the emulator reported as **offline** both when no emulator is running
*and* while one is still booting, so boot one first and wait for it:

```
Scripts/Android/start-emulator.sh  # boots, waits, never touches the app
skip app launch --android
```

The script is idempotent (a second run just confirms the running device), picks
the only installed AVD unless given a name or `$ANDROID_AVD`, and leaves the
emulator detached so it survives the script exiting or being interrupted. It
takes optional emulator flags: `Scripts/Android/start-emulator.sh <avd> -no-window`.

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

### Guest RAM

`EMULATOR_MEMORY` (default **4096**) sets the guest RAM `start-emulator.sh` boots
with. Do not lower it: at 3072 the guest pages into zram ~1.5GB deep, lmkd kills
continuously at `oom_score_adj` 965–985, and the app ANRs or cold-starts instead
of resuming — the `google_apis` image alone idles at ~650MB of Google apps. Below
4096 the script also passes `-lowram`, which is the only way past the emulator's
4096MB floor (`hw.ramSize` and `-memory` are both silently raised); check
`hardware-qemu.ini` in the AVD dir for what was actually used. Guest RAM dominates
the host footprint — HVF never hands a dirtied page back, so a long-running
emulator settles around 10GB; restart it rather than shrink it.

## Build

```
skip android build                     # transpile + compile via SwiftPM (fast inner loop)
Scripts/Android/build-release-apk.sh   # release APK, see releasing.md
```

Transpiled Kotlin lands under `.build/` (e.g.
`.build/plugins/outputs/android/FurAffinityUI/…/skipstone/`) — the worktree's for
`skip android build`, a [build slot](#build-slots)'s for a Gradle build. Run
`Scripts/Android/clean.sh` after changing `Skip.env`: the generated Gradle module
namespace is cached in both, though a slot also notices the change itself.

### Build cache

`org.gradle.caching` is on, so Gradle's local build cache
(`~/.gradle/caches/build-cache-1`) is shared by every worktree and outlives
`rm -rf .build`. It holds the Kotlin compiles of all Skip's included builds (SkipUI,
SkipLib, FAKit, …) and the dex merges, which took a fresh worktree from 314 s to
204 s. The transpiled Kotlin carries no absolute paths, so an entry built in one
worktree fits another. It does not cover the Swift: `buildAndroidSwiftPackageDebug`
declares no outputs and always runs, and so does `skip plugin --prebuild`; the
[build slots](#build-slots) cover that side. `:app:compileDebugKotlin` misses on a
new worktree because its BuildConfig carries the worktree's app id suffix, and every
`:app` task misses once after any change to `Android/build-slots/`, which changes the
settings classloader's hash. `Scripts/Android/prune-build-cache.sh`, which the
settings plugin runs before each build, caps the cache at 1.5× a clean `.build` by
dropping the least recently read entries. If a cached task looks suspect, bypass the
cache with `./gradlew --no-build-cache …`.

### Build slots

A Gradle build — `run.sh`, `debug.sh`, `./gradlew`, Android Studio — compiles the
Swift side in a **slot** shared by every worktree rather than in the worktree's own
`.build`, whose SwiftPM state is keyed by its path and so started cold in each new
worktree. `:app:assembleDebug`, measured 2026-09-28:

| Build | Wall | |
|---|---|---|
| a new worktree's first, own `.build` (before) | 134–235 s | prebuild 77 s, `buildAndroidSwiftPackageDebug` 97 s |
| the probe: a fresh checkout synced into a built copy | 15.1 s | its Gradle root in the copy too, so warm execution history |
| a new worktree's first, warm slot | 18.0 s at load 14, 24.3 s at 48 | sync 0 copied, prebuild 0.23 s; 34 tasks run, 10 from cache |
| rebuild in its slot | 8.9–16.8 s | a one-file body edit: 1 copied, that file compiled, 16.5 s |
| after `clean.sh` | 206.9 s | cold, as it should be; the next one is warm |

`Android/settings.gradle.kts` applies `fa.build-slots` (`Android/build-slots/`), which
replaces Skip's `skip-plugin` settings plugin and its paths hard-coded to
`rootDir/..`. The Gradle root, the `:app` outputs (`.build/Android/app`), the app id
suffix and `GIT_COMMIT` stay the worktree's. Each build:

1. **Leases a slot**, `~/Library/Developer/Xcode/DerivedData/android-slot-<n>/`: a
   source copy with its own `.build`, which keeps skipstone's upward search for
   `Package.swift` working. Under the pool lock (`DerivedData/.android-slot-pool.lock`,
   waited on with no timeout) it takes the idle slot this worktree used last, else,
   preferring one last built with the same `Skip.env`, the one whose recorded commit is
   fewest files away, else the least recently used; if every slot is busy it creates
   one, cold. An unleased slot a Swift build still runs in counts as busy: a `swift*`,
   `skip` or `clang` process with its cwd in the slot or a file open under its
   `.build`, as a cancelled build or a dead daemon leaves behind. The build names its
   pid; the one `lsof` costs 30–80 ms. Idle slots beyond `FA_ANDROID_SLOTS_MAX`
   (default 3) are deleted, least recently used first.
2. **Syncs** the worktree into it (`Scripts/Android/slot-sync.sh`): git's tracked and
   untracked-unignored files plus the generated catalog entries, never signing
   material.
3. **Prebuilds** there, with cwd and `PWD` set to the slot and no `OLDPWD`: SwiftPM
   keys its manifest cache on the environment, and the caller's `PWD` recompiled ~30
   manifests on every worktree switch (11–13 s). Other variables still count, so moving
   between the terminal and Android Studio, or setting `CI`, can cost ~11 s once.
   Before it, a base last built with another `Skip.env` drops its
   `.build/{plugins/outputs,Darwin,Android}`, where skipstone caches the package name
   and app id; the hash is in `.build/.skip-env-hash`, and a `.build` with a transpile
   but no hash counts as another. The base is the slot, or the worktree where slots are
   off.
4. **Includes** the slot's skipstone build and `skip-gradle`.

The lease is a `FileChannel` lock on `<slot>/.lock`, held by a build service that is
also a task-completion listener, which Gradle keeps open until the end of every build
— failed ones and IDE syncs included — and dropped by the OS if the daemon dies; a
compile error, a settings failure and `kill -9` of the daemon all left it free. These
are POSIX locks, which `flock(1)` does not see: probe them with Python's
`fcntl.lockf`, as `clean.sh` does. A deleted slot is first renamed to
`DerivedData/.android-slot-trash-*` and removed in the background, since Finder drops
`.DS_Store` files into it mid-`rm`; the next lease sweeps what is left.

Two measured rules shape the sync:

- **llbuild recompiles on an inode or mtime change alone**, so the copy is
  `rsync -rlp --checksum --no-times`: an identical file is not rewritten, and
  `.slot-manifest` only when the list changed.
- **`/usr/bin/rsync` is openrsync** (protocol 29), which ignored `--delete` and
  dir-merge filters and wiped a slot's `.build`. So nothing deletes through rsync:
  `<slot>/.slot-manifest` holds the last list, and a path that leaves it is removed.
  Nothing outside the list is ever touched.

**`rm -rf .build` is still a clean build**, in every slot the worktree built in. A
worktree has an id, in `$(git rev-parse --absolute-git-dir)/fa-slot-id`, which git
deletes with the worktree, and a token issued per clean, in `.build/.fa-slot-token`;
each slot it built in holds that token in `<slot>/.build/.slot-tokens/<id>`. The build
deletes the chosen slot's `.build`, and says so, when the worktree has an id but no
token (`.build` was deleted), or when the slot holds a token for its id other than the
worktree's (it predates that clean). A worktree with no id is new: it gets one, and a
token, and reuses a warm slot. The chosen slot then holds the worktree's token. The
tokens live in the slot's `.build`, so a wipe for any worktree takes them all along: a
stale one survives only in a slot the worktree has not built in since its clean.
`Scripts/Android/clean.sh` is the same wipe by name; `--all` also deletes
every idle slot and names the busy ones.

**Where slots are off**, the base is the worktree, as before:

- `FA_ANDROID_SLOTS=0`, set by `build-release-apk.sh`: it clears
  `.build/plugins/outputs` for the release app id, and its Sentry uploads are
  path-sensitive;
- `CI` (the GitHub workflows);
- `BUILT_PRODUCTS_DIR`, i.e. Xcode's "Run skip gradle" phase, whose transpiled output
  is already in Xcode's DerivedData;
- a relative `.package(path:)` in a synced `Package.swift` whose package the slot's
  copy lacks: its `Package.swift` is not among the synced ones, because it leaves the
  worktree, such as a [local fork clone](forks.md), or is git-ignored, missing or a
  nested repository. The build names it. An absolute path, `SKIPLOCAL` included, works
  from a slot.

`skip android build` and `test.sh` do not go through Gradle settings, so they build in
the worktree's `.build` (and `.build/android-test`, and FAKit's), cold in each new
worktree. `skip export` does run Gradle, with nothing in its environment that marks it,
so it takes a slot; release builds go through `build-release-apk.sh`, or
`FA_ANDROID_SLOTS=0 skip export`.
`FA_ANDROID_SLOTS_DIR` moves the slots' parent directory.

What this changes day to day:

- **Errors and DWARF paths name the slot.** Clicking a compiler error in Android
  Studio opens the slot's copy, and the next sync overwrites an edit made there. Edit
  the worktree. `debug.sh` maps the slot back to the worktree for LLDB, except
  `<slot>/.build`, where the package checkouts are. It takes the slot from the debug
  library's DWARF, since `.build/.fa-slot` names whichever slot Gradle configured last.
- **Generated output is in the slot.** Wherever these docs say
  `.build/plugins/outputs` or `.build/Android/skip-gradle`, a Gradle build's is under
  `$(cat .build/.fa-slot)/.build/`, and its segment after `outputs/` is
  `android-slot-<n>`. Android Studio indexes that Kotlin too: if another worktree has
  built in the slot since, the index shows its code until your next sync.
- **Disk.** A slot is ~3.0 GB, ~6.2 GB once a `profile` build has run in it
  (`run.sh --profile`, `check-crash-reporting.sh android`). A worktree's own `.build`
  (~1–7 GB), but its `Android/` (the `:app` outputs) and `.fa-slot*` files, is not used
  by Gradle builds, only by `skip android build`, `swift package update` and
  `build-release-apk.sh`, which recreate it cold:
  `Scripts/cleanup-worktree.sh --orphans` reports it and the slots, `--reclaim`
  deletes it, all of it, since a partial `.build` is what fails with "missing required
  module". Xcode's "Delete Derived Data" deletes the slots too, which only makes
  the next build cold; the script's own DerivedData sweep matches Xcode's 28-letter
  hashes and never takes a slot.

### Two sources of the Gradle version

`skip gradle` (and the Xcode `Run skip gradle` phase) shells out to the `gradle` on
`PATH` — the Homebrew one — and ignores `gradlew`. Android Studio uses the wrapper,
`Android/gradle/wrapper/gradle-wrapper.properties`. **Keep the two equal** (9.6.1
today); Skip also reads `distributionUrl` out of that file. Skip's catalog pins
Kotlin 2.3.0 / compileSdk 36 / JVM 17, and AGP 9.2.0, which we override to **9.4.1**.

That catalog is generated: skipstone writes it into `skipstone/settings.gradle.kts`
from skip-unit's `skip.yml`, so Android Studio's AGP Upgrade Assistant has nothing of
ours to edit. `FurAffinity/Skip/skip.yml` registers `android-gradle-plugin` ahead of
the default instead (skip-unit merges its catalog with `prepend`, and the first
registration wins). Bump it there.

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

### Known build warnings

A green `Scripts/Android/run.sh` still prints ~2000 warning lines. None of them
come from this repo's own sources any more — what was ours was fixed — so the
list below is what stays, and why. Check a *new* warning against it before
triaging the whole log again.

- **`skip-ui` fork** — `SkipUI/UIKit/UIImage.swift` "Skip is unable to match this
  API call to determine the correct actor on which to run it", and
  `SkipUI/Containers/Navigation.swift` "This extension will be moved into its
  extended type definition when translated to Kotlin". Fork territory; see
  [forks.md](forks.md).
- **Gradle 10 deprecations** — the whole "Deprecated Gradle features were used in
  this build" summary. `--warning-mode all` attributes every one of them to
  skipstone-*generated* `build.gradle.kts` files (`> Configure project
  :skipstone:FAKit` and `:skipstone:SkipBridge`): the `by extra` delegate syntax and
  "Using a Project object as a dependency notation". **None** to
  `Android/app/build.gradle.kts` or `Android/settings.gradle.kts`, which are ours —
  that is the check worth repeating if the summary ever grows. The same generated
  files also carry the Kotlin-level `srcDir` deprecation and "Redundant call of
  conversion method", and Skip's own generated
  `.build/Android/skip-gradle/src/main/kotlin/SkipGradlePlugins.kt` a deprecated
  `task(name:configureAction:)`.
- **"The Kotlin Gradle plugin was loaded multiple times in different subprojects"**
  — named subprojects are `:app`, `:FAKit` and `:SkipWeb`; the latter two are Skip's
  included builds, so the suggested fix (declare the plugin once on a common parent)
  is not reachable from here.
- **`clang: warning: using sysroot for 'MacOSX' but targeting 'iPhone'`** ×6 —
  SwiftPM linking the `.dylib` products during Skip's
  `swift build --triple arm64-apple-ios` pre-build.
- **"Detected multiple Kotlin daemon sessions"** — environmental: one daemon per
  worktree.

## Run

```
Scripts/Android/run.sh   # builds, installs, and starts this worktree's app
```

Boot an emulator first (see [Emulator](#emulator)) — this does not start one.

Every worktree installs its **own** debug app: `Android/app/build.gradle.kts`
derives an `applicationIdSuffix` and the launcher label from the worktree
directory name, so branches sit side by side on the single shared AVD instead of
overwriting one another (which is also what used to force `adb install -r -d`
past `INSTALL_FAILED_VERSION_DOWNGRADE`). Release is untouched.

That is why running goes through the script rather than
`skip app launch --android`: `skip` reads the app id from `Skip.env`, so it
installs the suffixed APK correctly and then starts an id that is not there.
`run.sh` builds with `./gradlew :app:installDebug` (the full pipeline —
see [shared sources](shared-sources.md#why-everything-unported-is-guarded) for
why that matters), reads the activity's package from `Skip.env`, and holds the
emulator lock while it runs.

`skip app launch --android` keeps its own job: it is the only command that
compiles the Darwin bridge, so it is how you prove that still builds.

**The bridge build can fail for reasons that are not your change**, reporting
`missing required module 'AndroidNDK'`/`'CJNI'` or `no such module 'OSLog'` while
emitting some unrelated dependency. Wipe `.build/Darwin` and retry; a single
failure proves nothing, so do **not** bisect your sources against one run:

```
for i in 1 2 3; do rm -rf .build/Darwin; skip app launch --android && break; done
```

See [Module-name poisoning](#module-name-poisoning) for what causes this class of
error and which two instances of it have been fixed.

A related trap with the same signature: a `from:` pin on `skip` drifts past the
installed CLI and the build fails *inside a dependency* (`AndroidUserDefaults` …
"must use a 'required' initializer"). The pin is `exact:` for that reason — keep it
equal to `skip version`.

Upgrading Skip therefore moves several things in one commit: `brew upgrade skip`
(machine-wide, so every other worktree now runs the newer CLI), the `exact:` pin in
`Package.swift` **and** `FAKit/Package.swift` **and** `Ceylo/Kingfisher`, and the
upstream merges into the skip-ui / skip-fuse-ui / skip-web forks. All of them must
name one location per Skip package — `github.com/skiptools/*` since Skip 1.9.6, the
old `source.skip.tools/*` is gone from the graph (see
[forks.md § One location per identity](forks.md#one-location-per-identity)). Then
`swift package update` (put non-Skip pins back if they drift), re-resolve the Xcode
project's `Package.resolved` the same way, and build from a clean `.build`. The
generated `SkipBridgeGenerated/*_Bridge.swift` for FurAffinityUI, FAKit and
Kingfisher are worth diffing against the previous build: a skipstone codegen change
shows up there first. If the build warns that Skip's `SkipSettingsPlugin` changed,
port the change to `Android/build-slots` and record the new hash it prints in
`SKIP_SETTINGS_PLUGIN_SHA256`.

The root `Package.resolved` **is** committed, so a branch-pinned fork needs its
refresh committed too — see [Forks](forks.md).

Corollary: `skip android build` and `skip android test` being green does **not**
mean the app still builds. Only `skip app launch` compiles the Darwin bridge, so
a change that genuinely breaks it can sit unnoticed through a commit.

### The shared emulator

There is one ~2 GB AVD for every worktree, and two of them installing or testing
on it at once fight over it while doubling the Gradle daemon's heap. Anything
that drives the emulator from a second worktree goes through the lock:

```
Scripts/Android/with-emulator-lock.sh skip android test --testing-library testing
Scripts/Android/with-emulator-lock.sh ./gradlew :app:connectedDebugAndroidTest
```

It waits (`--timeout`, default 1800 s), names the holder if the wait is real, and
exits with the wrapped command's status. The lock records the holder's pid, so
one left behind by a crashed run clears itself rather than deadlocking the next.
`run.sh` takes it itself — do not wrap that one.

### Module-name poisoning

Every target in an Android build shares one Modules directory, so **any** module
present in it answers `canImport(<name>)` for **every** target — including targets
that never declared a dependency on it. Whether it is present when a given target
compiles depends on build ordering, which is why this shows up as an intermittent
failure in a dependency you did not touch, and why the victim rotates.

Two instances have bitten this port. Both are fixed; recognise the shape if a
third appears.

1. **A module named `os`.** FAKit's compatibility target used to be called `os` so
   shared code could `import os` unconditionally. Once `os.swiftmodule` existed,
   `canImport(os)` was true on Android and whatever compiled next took its Apple
   branch: `Defaults` → `missing required module 'AndroidNDK'`,
   swift-android-native's `AndroidLogging` → `no such module 'OSLog'`, its
   `AndroidSystem` → `cannot find type 'os_unfair_lock'`. The target is now
   `OSCompat` and the three call sites choose with `#if canImport(os)`.

2. **`canImport(SwiftUI)` in FAKit.** On Android `SwiftUI` is SkipSwiftUI's façade,
   which reaches `CJNI` through SkipAndroidBridge → SwiftJNI. `CJNI` is a plain C
   target in `swift-jni`, and SwiftPM only puts its modulemap on a target whose own
   dependency closure reaches it — which FAKit's does not, so FAKit cannot compile
   that façade. `DynamicThumbnail` gated a `GeometryProxy`
   overload on `canImport(SwiftUI)`, so it compiled fine in debug (FAKit happened to
   go first) and failed the **release** build outright with
   `missing required module 'CJNI'`. It gates on `#if !os(Android)` now.

The rule: in a plain package, never gate on `canImport` for a module that Skip also
vends under that name. Gate on the platform.

`ANDROID_PACKAGE_NAME` in `Skip.env` **must** equal the Swift module name lowered
to a dotted namespace (`FurAffinityUI` → `fur.affinity.ui`); the generated app
resolves the transpiled module under that group, so a mismatch fails Gradle with
`Could not find <group>:FurAffinityUI:`.

## Debug

```
Scripts/Android/logs.sh                      # our tags only, live
Scripts/Android/logs.sh -a                   # every line from the app process
Scripts/Android/logs.sh -d | grep CFFALLBACK # how often the WebView fetch is used
```

The app logs far less than it emits: a typical minute is dominated by
`SkipWeb.WebView` resource lines and `chromium`. `logs.sh` filters by tag rather
than by pid, so it also keeps streaming across an app restart, where `--pid=`
goes silent. The tags it passes to `adb logcat -s` are `<app id>/FA`,
`<app id>/FAKit`, `<app id>/FAPages` and each Kotlin bridge's `TAG` — the app id
is derived from `Skip.env` (both with and without the per-worktree debug suffix)
and the bridge tags are read out of `Android/app/src/main/kotlin/`, so neither
drifts. Requires `adb` only at
`$ANDROID_HOME/platform-tools`, not on `PATH`.

`logcat -v color` paints the whole line, message included, which makes long URLs
hard to read. `--color` picks how much gets painted instead: `prefix` (the
default on a terminal) colors `<time> <level>/<tag>(<pid>):` in the level's color
and leaves the message on the terminal's own foreground, `level` colors only the
level letter, `full` is logcat's own whole-line color, and `none` — the default
when the output is piped — disables it.

`[CFFALLBACK]` tags every use of the WebView-fetch fallback — the slow path, up
to three navigations of 8 s polling. One line on entry, one on rescue, so a
fallback with no matching `rescued by WebView` line is one that failed. Since the
challenge coordinator landed, a healthy session shows **none at all**: challenges
are resolved by `FAChallengeView` and the retry goes through `URLSession`.

The **installed app id is `com.example.id1234`**, not `net.furaffinity.spike` —
plus, for a debug build, this worktree's suffix. So reaching the data directory
(the image cache lives at `cache/com.onevcat.Kingfisher.ImageCache.default`) is
`adb shell run-as com.example.id1234.<worktree> …`; `run.sh` prints the
id it starts, and `adb shell pm list packages | grep example` lists them all.

Every install drops the WebView's Cloudflare clearance, so the
next run shows FA's "Verify you are human" checkbox. It needs a **real click in the
emulator window**: synthetic `adb shell input tap` events do not clear it (that was
the cause of the old "CF loop").

The logged-out screen's **"Continue offline (debug)"** button (`AndroidRootView`)
drives ported screens without solving a Cloudflare challenge; its sibling
**"Continue offline, empty (debug)"** does the same with a session that has no
submissions, notes or notifications, which is how the feed's empty placeholder is
reached. Both are gated on
`android:debuggable` at *runtime* via `AndroidAppInfo.isDebuggable`, not `#if DEBUG`
— skipstone drops `#if DEBUG` blocks when it generates the view bridge, so a
compile-time fence there is silently inert. `OfflineFASession` and its demo data
therefore still ship in the release APK; that is the price of keeping the
affordance. The launch line reports which side of the gate a build is on:

```
Launched FurAffinity 1.19 on Android 17, debug build debuggable=true
```

That line comes from the shared `LaunchLog.swift`, so it matches iOS's word for
word; only the OS name and the trailing detail differ per platform.

Open `Android/` in Android Studio to attach a debugger to the Kotlin/JNI side (its
`.idea/` is git-ignored; `gradle.xml` there caches paths under `.build/` and is
regenerated on sync — as is `.gradle/config.properties`, whose loss is what makes
Studio warn about an invalid Gradle JDK).
**Never let Studio and `skip`/Xcode build at the same time**: both drive the same Swift
package through `skip android build`, and concurrent invocations fail with
`missing required module 'AndroidNDK'` and `error: cancelled`. Sequentially they are
fine — no wipe needed between drivers.
Swift-side logic runs natively (Skip Fuse), so `PersistentLogger` output appears
in logcat as well — tagged `<subsystem>/<category>`, e.g.
`com.example.id1234.<worktree>/FAKit`. The subsystem is the installed
applicationId for every module: `Bundle.main.bundleIdentifier` is nil in a plain
SwiftPM module here and names the Skip module rather than the install in the
bridged one, so `FALogSubsystem.override` is set from the Kotlin bridge at
startup (`FurAffinityUIRoot.onInit()`). A process that installs no override — the
`skip android test` runner, the Darwin bridge — falls back to `FurAffinity`.

That one write only reaches every module because `FALogging` is a package of its
own, and so is linked as one shared object. While it was a target inside FAKit,
`libFAKit.so` and `libFAPages.so` each carried a private copy of `override` (and
of `PersistentLogStore.shared`, which is the destructive half) — see
[One module, one image](shared-sources.md#one-module-one-image). Nothing at
runtime detects a relapse; `Scripts/Android/check-shared-globals.sh`, which
`run.sh` runs after the Gradle build, does.

### Attaching a Swift debugger

```
Scripts/Android/debug.sh    # build with symbols, install, start lldb-server, write .vscode/
```

Then set a breakpoint in a `.swift` file and press F5 in VS Code (**Swift
(Android)**). Its `preLaunchTask` reruns the script with `--no-build` — restarting
`lldb-server`, starting the app if needed, and opening `logs.sh -c` — so rerun the
script by hand only after a build it did not make: `run.sh` installs stripped
libraries. The attach is by process name, so an app restart costs one more F5.
**The attach leaves the app paused; press Continue once** — resuming from
`postRunCommands` makes lldb-dap abort with "Expected process to be stopped".
`.vscode/` is generated and git-ignored because the app id carries the worktree
name.

Android Studio can debug the Kotlin side at the same time (JDWP, not ptrace) if it
is set to **Java/Kotlin only**: its native/dual mode takes the ptrace slot LLDB
needs.

What it depends on:

- **`lldb-dap` from a swift.org toolchain, Swift 6.3+.** Xcode's LLDB lacks the
  Android fixes (module-load deadlock, attach crashes, pointer tagging).
- **The NDK's `lldb-server`**, copied into the app's data directory with `run-as`
  so it runs as the app's uid on a non-rooted device.
- **`-PfaDebugSymbols`.** AGP strips the *debug* variant too
  (`libFurAffinityUI.so` 13 → 7.3 MB), and LLDB reads modules off the device, so
  without it there are no line tables. Off by default: symbols for three ABIs slow
  the everyday build.
- **`assembleDebug`, then `installDebug -Pandroid.injected.testOnly=true`.**
  `lldb-server` ignores an APK's last entry
  ([llvm/llvm-project#173966](https://github.com/llvm/llvm-project/pull/173966),
  not in NDK 28.2); `assembleDebug` writes a `.so` last, and the re-pack puts a
  manifest entry there instead.

The generated `launch.json` also carries:

- **`"timeout": 300`.** A cold attach pulls ~400 modules (284 MB) into
  `~/.lldb/module_cache` and takes minutes; the 30 s default fails with
  `process failed to stop within 30 s`. Warm attaches take seconds, which makes
  that failure look intermittent.
- **`process handle -s false`** for the SIGSEGV/SIGBUS/SIGQUIT/SIGUSR signals ART
  raises in normal operation. Don't add `SIGPWR`: this LLDB rejects the name and
  drops the rest of the line.

A session that ends without detaching leaves the app SIGSTOPped (state `T`, pid
still alive); `debug.sh` resumes it.

#### Inspecting values

LLDB picks the expression SDK from the target triple, finds no `Linux.sdk` and
falls back to the host macOS SDK, so `p` fails with `could not build C module
'Dispatch'` and `po` crashes lldb-dap. `debug.sh` adds two settings to
`initCommands`, both read from the Swift SDK bundle's `swift-sdk.json`:

```
settings set target.sdk-path <bundle>/ndk-sysroot
settings append target.swift-module-search-paths <bundle>/swift-resources/usr/lib/swift-<arch>/android
```

Both are needed: without the SDK path the ClangImporter hits `#error Unsupported
architecture`. The module path is the `android` directory *below* the
`swiftResourcesPath` that `swift-sdk.json` names; the parent makes
`CoreFoundation` collide with the host toolchain's module map.

swift-foundation's `URL` is pure Swift, so LLDB's Foundation formatters miss it;
a `type summary` on `_url._parseInfo.urlString` shows it as a string in the
Variables panel. That is a private layout — if it changes, URLs show blank; use
`p url.absoluteString`. `Data` still shows as `slice`; use `p data.count`.

Verified 2026-09-12 with the generated `launch.json`, on a warm and a wiped module
cache: stopped in `OkHttpTransport.performBlocking`, `p request.url.absoluteString`
→ `"https://www.furaffinity.net/view/66303662/"`, `p data.count` → `372`,
`po response` → the full `FANativeHTTPResponse`, and the panel showed `request`'s
URL as a string.

## Test

```
Scripts/Android/test.sh
```

It runs both Android test packages on the running emulator, under
[the emulator lock](#the-shared-emulator), and fails if either reports fewer cases
than its floor in the script — a run that silently finds no tests must not pass:

- **FAKit** (FAPages, FAKit, FALogging), from `FAKit/`.
- **FurAffinityUITests** (the root package). It is the Xcode
  `FurAffinityTests` directory, compiled against `FurAffinityUI` with
  `FA_SKIP_MODULE` defined — each file picks its `@testable import` on that define.
  The target has no skipstone plugin, so SwiftPM honours its `exclude:`.

Left out of the root package, with the reason:

| iOS-only | Why |
|---|---|
| `BackgroundRefreshNotificationBuilderTests`, `NotificationCoordinatorTests` | BackgroundTasks, UserNotifications |
| `LoggedInViewTabTests` | the UIKit tab bar; Android has `AndroidRootView.Tab` |
| `ModelTests` (+ `MockFASession`) | `Model.init` observes `Defaults`, which on Android is a Kotlin SharedPreferences listener: it needs a JVM, and a native test executable has none |
| `SettingsMigrationTests.legacyUnmigrated…` | no pre-versioning Android install exists |

`skip android test --apk` would supply the JVM, but its harness (Skip 1.9.11) crashes
on **any** `@MainActor` test — a trap in libdispatch's main-queue drain, which it
drives from the Looper — so `ModelTests` waits on that.

The root package tests build in **their own scratch path**, `.build/android-test`.
In the worktree's `.build` they rewrite the skipstone plugin outputs that a Gradle
build reads when [slots](#build-slots) are off (CI, `FA_ANDROID_SLOTS=0`), and that
build then fails in Kotlin (`Unresolved reference 'ProcessInfo'`) until
`.build/plugins/outputs`, `.build/Darwin` and `.build/Android` are wiped.

A native test is an `adb shell` process, not an app: it has no `context.cacheDir`,
so the script sets `XDG_CACHE_HOME` for Kingfisher's disk cache. And `UserDefaults`
in a test file means SkipAndroidBridge's JNI-backed store (skipstone's typealias
arrives through `@testable import`) — reach the Foundation one `Defaults` uses as
`key.suite`.

### Toolchain vs. Xcode

The Swift toolchain and the Swift Android SDK (one version, installed together by
`skip android sdk install --version X`) must be at least as new as the Swift in
the Xcode that `xcode-select` points to: host code (the skipstone plugin,
manifests, the Darwin-side compile) builds against that Xcode's macOS SDK. Xcode 27
needs Swift **6.4**. A 6.3 toolchain on Xcode 27 fails in one of two ways: the
plugin can't import Foundation (`unknown argument: '-target-arch-variant'`, then
`cannot find 'URL'` and "build planning stopped due to build-tool plugin
failures"), or swift-frontend segfaults in `getObjCMethodCallee`
(skiptools/skip#733). Keep only one `*_android` SDK installed (`swift sdk list`):
with two, `skip android test` stops because the triple matches more than one SDK.

SwiftPM 6.4 defaults to the `swiftbuild` build system, which makes the Fuse
graph's "linked as a static library by …" duplication a hard error
(skiptools/skip#735). The Gradle build runs it since skip-bridge 0.18
(skiptools/skip-bridge#119), so every module of ours sits in exactly one image —
see [One module, one image](shared-sources.md#one-module-one-image). `test.sh` still
passes `--build-system native`: under swiftbuild, `skip android test` runs only the
first test target's runner it finds, and FAKit has three.

### CI

`build.yml`'s `Build Android App` job runs beside the iOS one, with no secrets:

1. `Scripts/Android/ci-setup.sh` — swiftly from swift.org's package, the skip CLI
   at the `exact:` pin (`check-skip-version.sh --install`: one past the pin fails far
   from the cause, see [Run](#run), and a Skip release must not turn CI red), and the
   Swift Android SDK. Not `skiptools/actions/setup-skip`: its `brew install skip`
   compiled swiftly and a JDK's openssl from source on the Intel runner, which has
   no bottles for them — 20 of its 27 minutes. The JDK is `actions/setup-java`, Gradle
   the wrapper (its user home cached by `gradle/actions/setup-gradle`), the Android SDK
   the runner's; SwiftPM's repository cache is cached too. The toolchain and the SDK
   themselves (8 GB) are downloaded each run: too big to cache usefully.
2. `SKIP_EXPORT_ARCHS=x86_64 ./gradlew :app:assembleDebug` — only a Gradle build
   compiles the Darwin bridge and the Kotlin, and x86_64 is the emulator's only ABI.
3. `ABI=x86_64 Scripts/Android/check-shared-globals.sh debug`, as `run.sh` does.
4. `Scripts/Android/test.sh` on an API 34 x86_64 emulator
   (`reactivecircus/android-emulator-runner`, AVD snapshot cached), logs uploaded.

It runs on **`macos-26-intel`**: the emulator needs nested virtualisation, which
GitHub's arm64 macOS runners do not have — the same choice as Skip's own
`skip-framework.yml`. GitHub retires its Intel macOS runners around **August
2027**. The way off is Linux with KVM, where `skip android test` works for
packages; Skip does not support a full app build there, so step 2 would have to
stay on macOS without an emulator (arm64 `macos-26`, as the release job already
does).

The iOS build must stay green at every step:

```
xcodebuild test -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

That device is this worktree's own — see the note in `AGENTS.md` §Tests, which is
also where the `OS=26.5` pinning trap a bare `name=` destination falls into is
explained.

## Wiping the build state

If a build fails with `missing required module 'CJNI'` across unrelated packages, the
incremental state is stale (typically after a `Package.swift` or FAKit change).
`Scripts/Android/clean.sh` always fixes it, at the price of a cold build. A partial
wipe is quicker but has to reach the slot, which only deleting the whole `.build`
does by itself (see [Build slots](#build-slots)). `S` is the slot the last Gradle
build used, or the worktree when slots are off; wipe it while no build runs there.
The three caches are the ones a `Skip.env` change clears:

```
S="$(cat .build/.fa-slot 2>/dev/null || pwd)"
rm -rf "$S"/.build/{plugins/outputs,Darwin,Android}
```

Under slots the worktree's own `.build/Android` is not among them: it holds the `:app`
outputs, which Gradle keeps up to date. With slots off it is the same directory, and
goes too.

If that is not enough (it is not, for a FAKit source or manifest change), drop the
SwiftPM build description too — it keeps `.build/checkouts`, so nothing is re-fetched:

```
rm -rf "$S"/.build/{aarch64-unknown-linux-android28,plugins,build.db,debug.yaml,Darwin,Android}
```
