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

## Test

The parser + logic layer is tested on the emulator via FAKit:

```
cd FAKit && skip android test --testing-library testing
```

From a second worktree, wrap that in
`Scripts/Android/with-emulator-lock.sh` (see [the shared
emulator](#the-shared-emulator)).

The iOS build must stay green at every step:

```
xcodebuild test -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

That device is this worktree's own — see the note in `AGENTS.md` §Tests, which is
also where the `OS=26.5` pinning trap a bare `name=` destination falls into is
explained.

## Wiping the build state

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
