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
FurAffinity/             ALL app sources — and the Skip target's directory
  Android/                 FurAffinityUIRoot.swift (bridged root view + app
                           delegate), AndroidRootView.swift
  Helper Views/Android/    Compose builds of the shared views, next to their
  Helpers/Android/         iOS/ counterparts — see AGENTS.md §Working Notes
  iOS/                     iOS-only sources + Info.plist, entitlements, icons
  Resources/               the Android asset catalog Skip mirrors
  Skip/skip.yml            marks this a native Skip module
Scripts/Android/         emulator, derived art
FAKit/                   shared Swift package (cross-compiles, see AGENTS.md)
```

### Why everything unported is guarded

Skip's transpiler (`skipstone`) walks the **entire** target-directory tree via its
`--project` flag; it honors neither SwiftPM `sources:` nor `exclude:`. Since the
target's `path:` is `FurAffinity`, that means every `.swift` in the app — 165 of
them — is offered to skipstone. Anything the Android build must not compile is
therefore wrapped, whole-file, in:

```
#if !FA_SKIP_MODULE
…
#endif
```

That covers the iOS-only files *and* the plain-SwiftUI screens that are simply not
ported yet. **Porting a screen is deleting its guard.**

`FA_SKIP_MODULE` is defined by `Package.swift` for this target. It has to be that
flag rather than `os(Android)`, because the module gets compiled **twice** for
Skip: the Android cross-compile, and a host build (`libFurAffinityUI.dylib`) where
`os(Android)` is *false*. An `os(Android)`-guarded file is therefore included in
the host build and its iOS-only imports have nothing to resolve against:

```
FurAffinity/Helpers/iOS/ImageBlur.swift:11:8: error: no such module 'Kingfisher'
```

Note which commands catch that: `./gradlew :app:assembleDebug` and
`skip app launch` both do. **`skip android build` does not** — it only
cross-compiles for Android and never runs the host build.

### Basenames must be unique across the tree

SwiftPM derives one object file per source *basename*, and skipstone one
`<Name>_Bridge.swift`, both flattened into a single directory. Two files with the
same name anywhere in the target fail the build:

```
error: couldn't build …/SkipBridgeGenerated/Zoomable_Bridge.swift
       because of multiple producers: Skip FurAffinityUI, Skip FurAffinityUI
```

This bites the `iOS/`+`Android/` substitution pairs, and a guard does not help —
the guarded file still *emits* a same-named (empty) bridge. Hence the eleven
`…+Android.swift` files; the directory still carries the platform meaning, the
suffix only keeps the name unique.

### Sharing asset-catalog entries

`FurAffinity/Resources/Assets.xcassets` is this module's own catalog, which Skip
mirrors into Android resources. To single-source an entry with the iOS catalog,
symlink the **`Contents.json`**, not the `.colorset`/`.imageset` directory:

```
mkdir Foo.colorset
ln -s ../../../Assets.xcassets/Foo.colorset/Contents.json Foo.colorset/Contents.json
```

Skip's resource copy does not follow a symlinked *directory* — it silently copies
nothing, and the entry never reaches the APK. The failure is quiet: `Color(_:bundle:)`
falls back to an opaque default, so a 10%-alpha border renders as a solid grey one
instead of erroring. After changing a catalog, confirm the entry actually landed
(the mirrored tree is itself made of symlinks, so `find -type f` won't list them):

```
ls -R .build/plugins/outputs/*/FurAffinityUI/destination/skipstone/FurAffinityUI/src/main/assets
```

The path segment after `outputs/` is the **checkout directory's name**, not the word
`android` — it differs per worktree, hence the glob.

### Generated art

An entry big enough that a second copy in git would hurt is generated from the iOS
art instead, and git-ignored. `Scripts/Android/generate-android-assets.sh` writes two sets:

- the in-app `AppIcon`, a 512×512 light/dark pair downscaled from two 1024×1024 PNGs
  (the view draws it at 100 pt);
- the launcher icon — `mipmap-*/ic_launcher_foreground.png` at the adaptive layer's
  108 dp and `mipmap-*/ic_launcher.png` at the legacy 48 dp, both from the light art
  (an adaptive icon has no dark variant).

`mipmap-anydpi/ic_launcher.xml` and `values/ic_launcher_background.xml` are
hand-written and committed. The art is a full-bleed rounded square whose subject
touches every edge, so the XML insets the foreground by 16.7% into the 72 dp safe
zone rather than letting a circular launcher mask clip the ears; the background is a
solid colour sampled from the art's yellow field, visible only in the parallax band.
Skip's template `<monochrome>` layer is gone — keeping it would leave Skip's sun as
the themed-icon variant.

`Android/settings.gradle.kts` runs the script at configuration time (first statement
in `pluginManagement`, same `providers.exec` mechanism as `skip plugin --prebuild`),
so a Gradle build or an Android Studio sync regenerates everything. That is the one
place that orders correctly for *both* consumers — the app module's resource merge
and the skipstone included build's resource copy — since an `app:preBuild` task
dependency cannot order against a separate included build. The script is therefore
written to be a true no-op when up to date, content-compared rather than rewritten.

`skip android build` goes through SwiftPM only and never runs Gradle, so it stays a
documented prerequisite; skipping it there costs a blank in-app icon. It is
idempotent and takes under a second:

```
Scripts/Android/generate-android-assets.sh
```

A SwiftPM prebuild plugin would be nicer, but it cannot work: `Image(_:bundle:)`
resolves through this module's catalog **in the source tree**, and the plugin
sandbox forbids writing there.

## Prerequisites

```
skip checkup                     # verifies toolchain (Xcode, Android SDK, Gradle, JDK)
skip android sdk install         # if the Android SDK/NDK is missing
Scripts/Android/generate-android-assets.sh   # derived art (see Generated art above)
```

## Emulator

Nothing in the Skip toolchain boots an AVD for you. `skip app launch --android`
fails with the emulator reported as **offline** both when no emulator is running
*and* while one is still booting, so boot one first and wait for it:

```
Scripts/Android/start-android-emulator.sh            # boots, waits, never touches the app
skip app launch --android
```

The script is idempotent (a second run just confirms the running device), picks
the only installed AVD unless given a name or `$ANDROID_AVD`, and leaves the
emulator detached so it survives the script exiting or being interrupted. It
takes optional emulator flags: `Scripts/Android/start-android-emulator.sh <avd> -no-window`.

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

### Our `os` module poisons whatever compiles after it

The compatibility target FAKit ships for `import os` ([Layout](#layout)) is *named* `os`,
so once `os.swiftmodule` exists in a scratch directory, every later target in that build
sees `#if canImport(os)` come out **true on Android** and takes its Apple branch. Three
known victims, none of which name the cause:

- `Defaults` (`Utilities.swift`) then does `import os` and fails with
  `missing required module 'AndroidNDK'` — it never declared that dependency, so
  AndroidNDK's modulemap isn't on its search path. AndroidNDK is a red herring.
- swift-android-native's `AndroidLogging` then does `@_exported import OSLog` →
  `no such module 'OSLog'`.
- swift-android-native's `AndroidSystem` then reaches for `os_unfair_lock` →
  `cannot find type 'os_unfair_lock' in scope`.

Nothing orders those targets after `os` (`AndroidSystem` isn't even a product, so we
can't depend on it), so this is a scheduling race: it stays invisible while they happen
to compile first, and a version bump that reshuffles the build — a bare
`swift package update <fork>` floating `skip` (`from: "1.9.4"`) past the installed CLI
(`skip version`) is one — is enough to lose it. Keep the `skip` pin equal to the CLI.

`rm -rf .build` does **not** fix it; this is not the stale-build phantom it imitates.
Recover by rebuilding each victim while `os` is absent:

```
M=.build/aarch64-unknown-linux-android28/debug/Modules      # Gradle's copy lives under
rm -f $M/os.swiftmodule $M/os.swiftdoc $M/os.swiftsourceinfo  # .build/Darwin/…/build/swift
swift build --swift-sdk aarch64-unknown-linux-android28 \
  -Xswiftc -DSKIP_BRIDGE -Xswiftc -DTARGET_OS_ANDROID --target Defaults
skip android build
```

(`--target AndroidLogging` / `--target AndroidSystem` the same way if those are what
failed.) A real fix means not owning a module called `os`.

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

The root `Package.resolved` **is** committed (`.gitignore` carries a `!/Package.resolved`
negation; `FAKit/Package.resolved` and the Xcode workspace's copy stay ignored). Three
deps resolve from mutable `branch: "android"` refs, so without the recorded revisions a
release APK isn't reproducible. Refreshing a fork is still
`swift package update <dep>` — now followed by committing the resulting diff.

Corollary: `skip android build` and `skip android test` being green does **not**
mean the app still builds. Only `skip app launch` compiles the Darwin bridge, so
a change that genuinely breaks it can sit unnoticed through a commit.

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
   which requires CJNI through SkipAndroidBridge → SwiftJNI — modules a plain
   SwiftPM package like FAKit cannot see. `DynamicThumbnail` gated a `GeometryProxy`
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
adb logcat | grep -i fur.affinity           # app logs (tagged fur.affinity.ui.FurAffinityUI)
adb logcat -s FurAffinityUI                  # or filter by tag
adb logcat -d | grep CFFALLBACK              # how often the WebView fetch is used
```

`[CFFALLBACK]` tags every use of the WebView-fetch fallback — the slow path, up
to three navigations of 8 s polling. One line on entry, one on rescue, so a
fallback with no matching `rescued by WebView` line is one that failed. Since the
challenge coordinator landed, a healthy session shows **none at all**: challenges
are resolved by `FAChallengeView` and the retry goes through `URLSession`.

The **installed app id is `com.example.id1234`**, not `net.furaffinity.spike` — so
`adb shell run-as com.example.id1234 …` is how you reach its data directory (the
image cache lives at `cache/fa_coil_cache`).

Every `skip app launch --android` drops the WebView's Cloudflare clearance, so the
next run shows FA's "Verify you are human" checkbox. It needs a **real click in the
emulator window**: synthetic `adb shell input tap` events do not clear it (that was
the cause of the old "CF loop").

The logged-out screen's **"Continue offline (debug)"** button (`AndroidRootView`)
drives ported screens without solving a Cloudflare challenge. It is gated on
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
xcodebuild test -scheme FurAffinity -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17'
```

(`OS=26.5` is not optional locally — see the note in `AGENTS.md` §Tests.)

## Update check

Settings shows the current and latest versions and a "Get …" link, from
`AppInformation.fetch()` against `api.github.com/.../releases/latest` — plain
`URLSession` on both platforms, since that endpoint wants no cookies and sits
behind no Cloudflare. One release feed serves both: tag `1.19` carries the IPA and
the APK, and draft releases are invisible to `releases/latest`, so publishing
stays manual.

`Bundle.main.version` reads 0.0.0 on Android, which would silently invert the
comparison; `FAAppVersion` is what makes it right (see the User-Agent section).

The tab badge reads `model.appInfo.isUpToDate == false` directly, same expression
as iOS. It used to go through a `Model.isUpdateAvailable` mirror, justified by
"Skip's bridge doesn't see changes to a *nested* `@Observable`" — that diagnosis
was wrong. Nesting has nothing to do with it: `AppInformation.swift` imported
`Observation` rather than `SwiftUI`, so the object got the stdlib registrar and
was inert. See [Every `@Observable` needs `SkipAndroidBridge` in
scope](#every-observable-needs-skipandroidbridge-in-scope). One import fixed the
badge and Settings' "Latest available version" row together, and the mirror is
gone.

## Release signing

The release `signingConfig` in `Android/app/build.gradle.kts` falls back to the
**debug** key when `keystore.properties` is absent, so out of the box
`assembleRelease` emits a debug-signed APK and exits 0. That is unrecoverable
once shipped: everyone who installed it must uninstall before they can take a
properly signed update. A `gradle.taskGraph.whenReady` check now fails any
`assemble/bundle/package/installRelease` task while the file is missing. The debug
variant is unaffected, and configuring the project without a keystore still works.

Both files live beside the module (`storeFile` resolves relative to
`Android/app/`) and are git-ignored:

```
keytool -genkeypair -v \
  -keystore Android/app/keystore.jks -alias furaffinity \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Ceylo, O=Ceylo, C=FR"
```

```properties
# Android/app/keystore.properties
storeFile=keystore.jks
storePassword=…
keyAlias=furaffinity
keyPassword=…
```

**Back `keystore.jks` up off-machine before building anything with it.** Losing it
permanently ends the upgrade path for every installed user, and Google's developer
verification (sideloading included, from late 2026) registers a package name bound
to this certificate — neither can be changed afterwards.

Check what a build actually got signed with:

```
apksigner verify --print-certs <apk>      # must NOT say CN=Android Debug
```

## Handing a build to testers

```
git stash apply stash@{0}          # pbxproj id + Amplitude key + Skip.env id
rm -rf .build/plugins/outputs .build/Darwin .build/Android    # applicationId changed
skip export -d out --release --android --no-ios --no-export-project
```

`--no-ios` because the Skip-generated iOS shell is not this app's iOS release path.
**`--no-export-project` is not optional**: the source-archive step walks the project
directory, and with `-d out` inside it that includes its own output — it recurses
until the zip is 1.37 GB and then fails. You do not want the archive anyway; the
Android source is private. Output is `out/FurAffinityUI-release.apk` (send this) plus
an `.aab`, which nothing here uses since Play is out.

`assembleRelease` puts the same APK at
`.build/Android/app/outputs/apk/release/app-release.apk` — note `.build/`, not
`Android/app/build/`; Skip redirects `buildDir`.

`skip export` never touches adb — it only writes artifacts. To try the exported APK
on a running emulator or device, install it by hand and launch it from the icon:

```
adb install -r -d out/FurAffinityUI-release.apk
```

`-d` (allow downgrade) because this worktree's versionCode 11900 is ahead of the
other worktrees'. `-r` alone still fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
if a *debug*-signed build of the same applicationId is installed — that one needs
`adb uninstall ceylo.FurAffinity` first, which wipes the FA session cookies.
The applicationId is `PRODUCT_BUNDLE_IDENTIFIER` (`ceylo.FurAffinity` with the stash
applied), **not** `ANDROID_PACKAGE_NAME` (`fur.affinity.ui`, the module package). To
launch from the shell rather than the icon:
`adb shell monkey -p ceylo.FurAffinity -c android.intent.category.LAUNCHER 1`.

Measured 2026-08-16, release, `arm64-v8a`: **94 MB**. A universal APK with debug
symbols was 436 MB; stripping took it to 249 MB and the ABI filter to 94 MB. The
stripping only works with the NDK installed (`sdkmanager "ndk;28.2.13676358"`) —
without it AGP's `stripReleaseDebugSymbols` silently copies the libraries through.
`lib_FoundationICU.so` stays ~40 MB of the total; that is ICU data, not symbols.

R8 and resource shrinking run clean. The existing `-keep class fur.affinity.ui.**`
already covers every Kotlin bridge reached by name through `AnyDynamicObject`
(`FAAppInfoBridge`, `FACoilBridge`, `FACookieBridge`, `FADefaultsBridge`,
`FAMediaBridge`, `FADefaultsObserver`) — verified present in the release DEX.

What to tell a tester:

- **Android 9 or newer** (minSdk 28), **arm64 only** — a 32-bit-ARM phone will refuse
  to install it. 18+, and it needs a furaffinity.net account.
- Not ported yet: Notes, Notifications, the Profile tab, Explore/search, story (text)
  and audio submissions, and posting comments. Tapping an author or an avatar shows
  "This screen isn't ported to Android yet."
- First launch shows Cloudflare's "Verify you are human" and needs a real tap.
- There is **no crash or ANR reporting on either platform**, so a hang has to be
  reported by hand — Settings → Export Application Logs is what to ask for.

## Defaults

`UserDefaults.standard` means two different things on Android. In a module Skip's
transpiler processes, skipstone emits `typealias UserDefaults = AndroidUserDefaults`,
so `.standard` is the app's `SharedPreferences` (`shared_prefs/defaults.xml`) — where
`@AppStorage` and raw `UserDefaults` writes land. `Defaults` is a plain SwiftPM
dependency compiled untouched, so *its* `.standard` is Foundation's own instance: a
separate store nothing else reads, and one that never reaches disk here.

That is why `Defaults[key] = value` used to vanish silently while reads returned the
new value — both ends were talking to the orphan store. The fork exposes
`Defaults.defaultSuite` for it, and `FurAffinity/Helpers/Android/AndroidDefaultsSuite.swift` assigns
the shared-preferences-backed one from `onInit()` (`Application.onCreate`), which has
to happen before the first key is created: a key captures its suite and registers its
default value into it right away. `Defaults.runSettingsMigrations()` touches keys, so
it runs *after* `installDefaultsSuite()` in `onInit()`.

Serialization is *not* a problem: `set(_:Any?, forKey:)` carries `Bool`, `Int` and
`String` across JNI to shared_prefs unchanged (measured), so no typed-setter routing
is needed.

`@Default(.someKey)` works on Android too, and shared screens spell it exactly as on
iOS. `Ceylo/Defaults@android` guards the package's SwiftUI support out (importing
SwiftUI → SkipUI → CJNI from a plain SwiftPM package breaks the build), so the app
module re-declares the wrapper over `@AppStorage` in `FurAffinity/Helpers/Android/AndroidDefault.swift`.
Correct storage isn't enough to drop that re-declaration: skipstone matches state
property wrappers by *attribute name* when it generates a view's bridge, so a wrapper
it doesn't know about gets no `initState` entry and never triggers recomposition. The
wrapper has to own a Compose-visible box, which `@AppStorage` provides. It is reactive
to writes from anywhere via `AppStorageSupport`'s SharedPreferences listener.

To check what actually persisted — never trust a read-back of `Defaults[…]`, that is
what hid this:

```
adb shell run-as com.example.id1234 cat shared_prefs/defaults.xml
```

## Forks

| Fork | Why |
|---|---|
| `Ceylo/Defaults` | Android port; `Defaults.defaultSuite` (see [Defaults](#defaults)) |
| `Ceylo/Kingfisher` | Android port |
| `Ceylo/skip-ui` | `listRowInsets` (and innermost-wins `listRow*` precedence); resuming an in-flight animation across composition disposal; `Text(bridgedHTML:…)`; `Text(bridgedRichText:bridgedInlineViews:)`; `Text(bridgedSegments:…)`; `FlowRow`; SF Symbol mappings; iOS-parity text layout (HTML line height, `.subheadline` weight, menu text/icon size, menu divider) |
| `Ceylo/skip-fuse-ui` | the Fuse side of each: `listRowInsets`, `Text(html:…)`, `Text(AttributedString)` / `Text(_:inlineViews:)`, `Text.+`, `FlowRow`, plus `glassEffect`/`AnyTransition.animation` un-`unavailable`d |

All on an `android` branch, referenced by URL + branch from `Package.swift` (and,
for Defaults/Kingfisher, the Xcode project too). While iterating, re-point the root
`Package.swift` at a local clone:

```
.package(path: "../../SkipForks/Defaults")     // instead of the URL + branch
```

then push to the `android` branch before the step's gate.

**Do not run `skip android build` / `skip android test` inside a fork checkout.**
A framework package has no `.xcodeproj`, so both build modes share one `.build/`, and the
Android/bridge pass strips the transpiled Kotlin out of
`.build/plugins/outputs/skip-{lib,foundation,model,unit}/…/src/main/kotlin` without
invalidating the `.Skip<Module>.sourcehash` files that llbuild tracks. skipstone is
therefore never re-invoked for them, and the next `swift test --filter XCSkipTests` fails
with thousands of `Unresolved reference 'sref' / 'MutableStruct' / …` that look like source
errors but are just empty dependency jars. Recovery: `rm -rf .build/plugins/outputs`. The
app worktree is immune — there `skip android build` writes to `.build/Darwin/DerivedData/`
instead.

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

A second patch to the same file fixes how *nested* `listRow*` modifiers resolve.
`ListItemModifier.combined(for:)` kept the first non-nil value it saw and
`Renderable.forEachModifier` walks outermost → innermost, so an ancestor's
`listRowInsets` / `listRowBackground` / `listRowSeparator` overrode the row's own —
the opposite of SwiftUI, which resolves them innermost-wins. That silently gave
`SubmissionView`'s comment rows the ancestor's 5 dp/5 dp vertical insets, and those
pad the Compose `Box` *wrapping* the row content: dead space outside the SwiftUI view
`CommentThreadConnector` overlays, which can only paint inside its own row. The thread
lines therefore stopped at each row's edge with a visible gap. The fix is to overwrite
on every non-nil visit instead, so the last (innermost) value wins.

A third patch, to `Animation/Animation.swift`, is about the *recycling boundary*. A `List`
row is a `LazyColumn` item, so scrolling it out of the composed window disposes its
composition; Compose's `SaveableStateProvider` restores `rememberSaveable` slots on the way
back but not plain `remember` ones. A value animation straddles that line:

| slot | primitive | survives recycling? |
|---|---|---|
| the `@State` powering the animation | `rememberSaveable` | **yes**, already at its target |
| `rememberedValue` / `hasChangedValue` in `View.animation(_:value:)` | `rememberSaveable` | **yes** → `isValueChange` is false, so `_animation` is never republished |
| the `Animatable` in `toAnimatable` | `remember` | **no** → recreated *at the target value* |
| `onAppear`'s `hasAppeared` | `remember` | no → it fires again, but writing `true` over `true` is a no-op |

Everything that would restart the animation is gone and everything that would let it finish
says it already has, so from the second composition on the row paints the end state
statically and permanently — however much of the animation was still to run. `toAnimatable`
already had the machinery in the saveable `resetValue`, but reserved it for restarting
*infinite* animations. The patch generalises it to a record of the animation, its start
value, its target and the uptime it started at, and resumes from that record: the
`Animatable` is recreated at the start value and the spec re-run carrying a
`StartOffset(elapsed, FastForward)`, so the animation picks up where disposal interrupted
it. Past its end it snaps to the target, as it would have anyway; only duration-based specs
get a record, since a spring has no play time to offset into.

That is what the deep-linked comment's highlight pulse needed: it was only ever visible when
the row's very first composition happened to land on screen.

**Note:** skip-ui arrives transitively via skip-fuse-ui, so overriding it needs its own
entry in `Package.swift`'s `dependencies`, not just the fuse-ui one.

### The other fork patches

- **`Text(html:)`** hands markup to Compose's own parser,
  `AnnotatedString.fromHtml`, which is how FA's rich text is rendered. It is worth
  preferring over anything built on styled runs for one reason above all: it applies
  **`ParagraphStyle(textAlign)`**, so a `[center]` block and the text around it live in
  one `Text`. Compose applies `textAlign` per text node, so styled runs cannot express
  that at all — the previous design had to break every block into its own view.
  It also handles weight, emphasis, decoration, baseline, `font color`,
  `span style="color:…"`, `h1`–`h6`, `br`/`p`/`div`, `ul`/`li` and `a href` unaided.
  Three things it does not do, and what covers each:
  - `<code>` is unrecognised, and alignment is read only from `style="text-align:…"` on a
    *block* element and only as `start`/`center`/`end` — never `left`/`right`, never
    `align="…"`. FA compiles `[center]` to a class on `<code>`, so `FAHTMLNormalizer`
    rewrites it. That pass is also where FA's other markup quirks are absorbed; it is
    unit-tested on iOS against the same fixtures the parser suites use.
  - `<hr>` is dropped without even a line break, so the normaliser hoists every rule to a
    direct child of the root — splitting whatever it sits inside, or the markup after it
    loses its opening tag — and `HTMLView` draws a `Divider()` between the pieces.
  - `<img>` is dropped but **leaves a U+FFFC behind**, which is exactly the marker inline
    content splices at. `RichText.splicingInlineContent` rebuilds the parsed string with
    `AnnotatedString.Builder.append(text:start:end:)`, which carries each range's spans
    with it. Transpiled, its loop iterates UTF-16 code units — the unit Compose counts
    offsets in — so an emoji earlier in the text cannot shift a placeholder.

  A tapped link must not reach Compose's own `UriHandler`: it would open the browser
  before the app saw the URL. A `LinkInteractionListener` hands it to `onLinkTap`
  instead, and `HTMLView` marks it with the app scheme so `AndroidRootView`'s existing
  handler still tells an in-app FA link from an "Open in Web Browser".
  Parsing is `remember`ed on the markup and the link colour — `Render` runs on every
  recomposition, and the styles bake the colour in.
- **`Text.+`** is `@available(*, unavailable)` upstream. The obstacle is that a `Text`'s
  modifiers are stored as closures applying *environment-based view* modifiers, and
  Compose needs one `AnnotatedString` with a `SpanStyle` per segment — so each modifier
  also records into a `TextRunStyle`, purely additively, leaving a standalone `Text`
  untouched. Operands cross as fully-formed `SkipUI.Text`s (so keys, tables, bundles and
  locale resolve at compose time as usual) alongside one `RichText` record each with an
  empty text field. Reading a `ShapeStyle` as a colour needs the `RichTextColorStyle`
  protocol rather than casts — `AnyShapeStyle` erases its base and `OpacityShapeStyle` is
  generic over it — and `HierarchicalShapeStyle`'s conformance has to sit in that type's
  own file, since its `level` is `private`. Anything that cannot cross as a `SpanStyle`
  (`tracking`, a non-monospaced `fontDesign`, `font(.custom)`, a gradient or material
  `foregroundStyle`, an operand with inline views) raises a `preconditionFailure` naming
  the modifier: silent dropping is the failure mode this port keeps hitting.
- **`Text(AttributedString)`** is `@available(*, unavailable)` upstream, which blocks all
  rich text. The first cut bridged it as markdown, since SkipUI's own rich-text model is
  markdown — but markdown cannot express colour, font size, underline or baseline at all,
  and FA's markup is built from exactly those. So runs now cross as records:
  `SkipUI.Text(bridgedRichText:bridgedInlineViews:)` takes one record per run (RS-separated,
  fields US-separated) and builds the `AnnotatedString` with a `SpanStyle` each. That init
  deliberately bypasses `LocalizedStringKey`: the content is user data and must not be
  bundle-looked-up or `String.format`ed. The encoder reads a subset of
  `AttributeScopes.SwiftUIAttributes` — `\.font`, `\.foregroundColor`, `\.underlineStyle`,
  `\.strikethroughStyle`, `\.baselineOffset` — which SkipSwiftUI declares itself, but
  **only where SwiftUI's own is absent**: declaring it on Darwin makes
  `AttributeScopes.SwiftUIAttributes` ambiguous and the build fails. It returns nil when
  the string carries no styling at all, and `Text` then falls back to `verbatim`.
  - Colours cross as **decimal** ARGB, or as a `primary`/`secondary`/`accent` token the
    composition resolves: SkipLib's `Int64(_ string:)` has no radix parameter.
  - The separators are spelled `\u{001E}`/`\u{001F}` with all four hex digits. Skip's
    transpiler emits `\u{1E}` as the Kotlin `"\u1E"`, which is not a valid escape.
  - **`Text(_:inlineViews:)`** splices views in at the object-replacement characters, in
    order — SwiftUI's spelling is `Text(Image(…)) + Text(…)` concatenation, and it is
    `Text(Image:)` that is unavailable here, not the concatenation. `TextInlineView` carries an explicit size because Compose reserves
    the placeholder's space before it ever composes the view. Use
    `PlaceholderVerticalAlign.Center`, not `TextCenter` — the `Text*` alignments fit the
    placeholder into the text's own vertical bounds, so a 50 pt avatar spills onto the line
    below. Even then it overlaps until the text's style drops its fixed `lineHeight`, which
    Material's typography always sets.
- **`FlowRow`** replaces SwiftUI's `Layout` protocol, which SkipUI doesn't implement and
  which can't be emulated: a `Layout` enumerates and places its subviews, and an opaque
  `Content` gives a Fuse module no access to them. Compose wraps natively, so it is a
  container instead, with `FurAffinity/Helper Views/Android/FlowLayout+Android.swift` keeping the iOS call signature.
- **`glassEffect`** and **`AnyTransition.animation`** become pass-throughs rather than
  `unavailable`. `#available(iOS 26, *)` is vacuously true off-Apple, so a shared source
  takes its Liquid Glass branch on Android; making the call unbuildable is worse than
  ignoring an effect Compose can't express.
- **SF Symbol mappings** for the symbols this app uses (`safari`,
  `square.and.arrow.down`, `bubble`, `exclamationmark.bubble`, `ellipsis.bubble`,
  `message`, `text.badge.star`). Unmapped names render as a warning triangle.
- **Text layout parity with iOS.** Four Material defaults that each read as a bug next
  to the iOS build, all measured off screenshots rather than eyeballed:
  - Material's typography **fixes a line height** (`bodyLarge` is 24sp on a 16sp face,
    1.5x) where SwiftUI leaves multi-line text at font metrics — so an HTML body ran
    24 dp per line against iOS's ~17.9 pt. The HTML branch now clears `lineHeight` and
    falls back to font metrics (18.7 dp measured). The inline-content path already did
    this for a different reason — a placeholder taller than the fixed height overlaps
    its neighbours — which also meant a description *with* an avatar in it rendered at
    a different density than one without. `richText`, `segments` and markdown keep M3's
    line height.
  - **`.subheadline` mapped to `titleSmall`**, which is Medium 500. iOS's subheadline is
    regular-weight secondary body text, so every username, byline and timestamp read
    heavier than its counterpart. `bodyMedium` has identical metrics (14sp/20sp, so the
    size assertions in `TextTests` are untouched) at weight 400 — 19% less ink for the
    same bounding box. Note the *size* gap (14sp vs 15pt) is deliberate; see the manual
    offsets in `Text/Font.swift`.
  - **`DropdownMenuItem` supplies `labelLarge`** (14sp Medium), far under what a SwiftUI
    menu item renders at. Setting the environment font to `.body` around the items
    restores `bodyLarge`; because `Image.RenderScaledImageVector` sizes menu icons to the
    current text style, the icons follow from the same change (14 → 16 dp). It goes in
    `RenderDropdownMenuItems`, which `ContextMenu` shares, and a `.font()` on an
    individual `Label` still wins. The environment setter must be spelled
    `$0.setfont(…)`: skipstone emits a Swift `var` with a custom getter as a Kotlin `val`
    plus a `setX` function, so `$0.font = …` transpiles to code that will not compile.
  - **A `Divider` inside a menu is invisible.** `Color.separator` resolves to
    `surfaceColorAtElevation(3.dp)` and a `DropdownMenu`'s own container sits at
    elevation 3 — so the rule is drawn in exactly the menu's background colour. Menus now
    draw theirs with `outlineVariant`. Two places needed it: the `Section` branch, and a
    new `stripped is Divider` branch, without which an explicit `Divider()` in the menu
    content fell through to a plain `Render` and vanished. The global `Color.separator` is
    left alone — outside a menu it sits on a non-elevated background and shows fine.

  Not changed, as intended Material behaviour: the type-scale **sizes**, M3 letter
  tracking, the 48 dp menu row height, and trailing menu-icon placement (the `leadingIcon`
  slot carries the `Picker` selection checkmark).

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

- **Never push a `Cookie:` header that lost its `cf_clearance`.** Coil cannot pull
  a fresh header per request the way the HTTP layer can, so
  `FAWebSession.refreshedCookieHeader()` is the one place that keeps the two in
  step — and a header read *mid-wipe* has no clearance at all. Pushing that
  de-seeds the image layer and every subsequent request's `Cookie:` line, turning
  one challenged fetch into a stampede. The guard is timing-free: if the incoming
  header carries no clearance and the last pushed one did, hand the last-good one
  back. Expiring the cookie locally does not invalidate it at the edge, so
  replaying it is correct, and `pushedCookieHeader` already *is* the last-good
  header — no new state. `String.carriesCloudflareClearance` (in FAKit, so
  `StringFATests` covers it under the iOS gate) matches the cookie *name*: a plain
  `contains("cf_clearance=")` would also accept `xcf_clearance`.
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

## Login and the long-lived WebView

The logged-out screen is the shared `HomeView` — same icon, buttons and footer as
iOS, from the same file. Four things in it needed handling, all of them the general
rules in [Rules for shared sources](#rules-for-shared-sources) applied once each:

| In HomeView | Guard |
|---|---|
| the Liquid Glass button branch | `#if FA_SKIP_MODULE` takes the pre-iOS-26 capsules instead. `#available(iOS 26, *)` is vacuously true off-Apple, and `GlassButtonStyle` is unavailable / `.glassProminent` absent. The capsule pair lives in `legacyButtons` so the `#if` holds balanced braces |
| `ErrorDisplay`, `NotificationCoordinator` | `#if !FA_SKIP_MODULE`; errors reach the user through `AndroidRootView`'s banner, and nothing delivers notifications here |
| the six `@State`/`@Environment` wrappers | internal, not private |
| `UIApplication.shared.applicationState` | dropped from a log line that already carries `scenePhase` |

`FurAffinity/Helper Views/Android/FALoginView.swift` is the Android substitute for FAKit's WebKit one,
matching its public surface (`session` binding, `onError`, `makeSession()`) so the
shared caller compiles unchanged. It cannot live in FAKit — it needs skip-web (see
`FAHTTPDataSource` for the CJNI rationale) — and it is unguarded, so the Darwin
bridge compile finds it too; this module's declaration shadows FAKit's.

### Why a hidden WebView is mounted for the whole session

`FAWebSessionView` (in `FAWebSession.swift`) keeps a 1×1, `opacity(0.001)`,
hit-testing-disabled WebView at the root of `AndroidRootView` for the life of the
app, the way `RootView` does with `FAChallengeView` on iOS. Two things need a live
WebView long after any login screen is gone:

- `cf_clearance` is bound to the byte-exact WebView User-Agent, which is read out of
  a real WebView via JS (a 1 dp one runs scripts fine — verified).
- `FAHTTPDataSource`'s fallback for a challenged request is to navigate a cleared
  WebView and read the DOM.

So `FAWebSession.shared` owns the navigator, and `establishSession()` — cookies →
`OnlineFASession` — always runs against *it*, never against a screen's own WebView.
Cookies are process-global on Android (`CookieManager`), so the hidden WebView sees
whatever clearance and auth the visible login sheet just earned.

`makeSession()` (autologin) first `awaitReady()`s that view's first
`onNavigationFinished`: a `WebViewNavigator` with no attached engine returns an
*empty cookie list* rather than an error, so a cold-launch autologin that skipped
the wait would silently look logged out.

Costs worth knowing: while the login sheet is up there are two WebView instances,
and the hidden one loads FA's home page — ads and all — once per launch.

### The WebView User-Agent carries the app identifier (measured 2026-08-16)

FA staff identify this app's traffic by a `ceylo.FurAffinityApp/<version>` suffix on
the User-Agent; iOS appends it via `WKWebViewConfiguration.applicationNameForUserAgent`.
Android now does the same through skip-web's `customUserAgent`, computed once in
`FAWebViewUserAgent` (`FAWebView.swift`) as the platform default plus
`FAUserAgent.applicationName`, so the suffix can't drift from iOS's.

**All three `WebEngineConfiguration` sites must carry it** — `FALoginView`,
`FAChallengeView`, `FAWebSession` — because `cf_clearance` is bound to the byte-exact
UA while the cookie jar is process-global: a clearance minted by any one of them is
replayed by all. Leaving one un-overridden mints under the bare UA and 403s everything
after. skip-web applies it at engine construction, so no navigation can precede it.

Everything downstream still reads the UA *live* out of the WebView
(`FAWebSession.swift` → `liveUserAgent()` → `FAHTTPDataSource` and
`CoilImageLoader.configure`). The computed string is an input to the WebView only; the
WebView stays the single source of truth. `[CFDIAG] User-Agent drifted=` in the
challenge diagnostics compares the two.

Three earlier comments claimed setting `customUserAgent` "empties
`navigator.userAgentData`, which Cloudflare reads as a bot signal". **Measured false**:
with the override in place the emulator reports
`{"mobile":true,"platform":"Android","brands":[…Android WebView 151, Chromium 151]}`,
and a cold launch clears the challenge and loads the feed with thumbnails. No
`WebSettingsCompat.setUserAgentMetadata` and no fourth skip-web fork are needed.

One expected consequence: the suffix embeds the app version, so **an app update changes
the UA and invalidates any persisted `cf_clearance`**. It is re-minted on the next
challenge; the first launch after an update showing `[CFDIAG] cf_clearance drifted=true`
and a round of 403s is that, not a regression.

`Bundle.main.infoDictionary` is *empty* in a Skip Fuse native module (corelibs
Foundation, no Info.plist), so the version behind that suffix comes from
`FAAppInfoBridge.versionName()` — the package manager — and is installed into
`FAUserAgent.appVersionOverride` from `onInit()`, before any WebView exists.

### What actually draws the Cloudflare challenge (measured 2026-08-12)

Two candidate causes were tested and both are settled.

**The duplicated `Cookie` header was real, and was not the cause.** Every request
used to send every pair twice (`FAWebSession` derives the base header and
`OnlineFASession`'s auth cookies from the same jar, and the merge concatenated
them). Fixed by merging on name. Measured A/B inside one session — a marker file
in the cache dir flipped the behaviour per launch, arms alternating, so the
bursts described below could not favour one arm:

| Arm | Challenged requests | Wilson 95% |
|---|---|---|
| A — deduped | 8/9 (88.9%) | [56.5%, 98.0%] |
| B — duplicated | 6/7 (85.7%) | [48.7%, 97.4%] |

Null, per the rule fixed before the run. Read it with the caveat that both arms
sat near the ceiling: the window was a saturated one, so the test had little
power to detect a smaller effect. It rules out "duplication is what breaks
autologin"; it does not prove duplication is free. The fix stands on its own —
no browser sends a pair twice.

**It is not the emulator either.** Same minute, same egress IPv4:

| Client | Result |
|---|---|
| App URLSession (WebView UA + full cookie header) | `403 cf-mitigated: challenge` |
| Mac `curl --http1.1 -4`, same UA + same cookies *(bad clearance — see below)* | `403 cf-mitigated: challenge` |
| Mac curl, no cookies / default UA / desktop Chrome UA | `403` in all three |
| **Emulator Chrome, same IP** | **full page, no interstitial** |

It is not the address, then. The conclusion drawn at the time — "the
discriminator is browser engine vs bare client" — **was over-claimed**, and what
actually settled it is below.

**The hidden WebView cannot solve a challenge, which is the real defect.**
Emulator Chrome cleared the interstitial unattended in under 15 s; the 1×1,
`opacity(0.001)`, hit-testing-disabled WebView sat on `Un instant…` through
three navigations and ~60 s.

### Why the hidden WebView never cleared it (measured 2026-08-12, later)

Dumping what the engine was actually looking at answered it. The interstitial
declares `cType: 'managed'` — the *passive* kind, no click required — and loads
Turnstile with `render=explicit`. `window.turnstile` was present, no JS errors,
every challenge resource fetched 200. Two things were wrong:

**The widget had no room.** Inside the 1×1 frame the WebView's viewport is 4 CSS
pixels wide, and Turnstile's container measured **0 × 69**. Widening the frame
made the same container measure 358 × 69. A widget that cannot lay out cannot
report, so the managed challenge never completed and the page stayed on
`Un instant…` forever. (The widget's own iframe lives in a *closed* shadow root,
so `document.querySelector('iframe[src*="challenges.cloudflare.com"]')` — what
`FAChallengeView`'s DOM probe looks for — can never find it. Measure the
container instead.)

**We kept handing Cloudflare its own escalation counter.** The jar held
`cf_chl_rc_ni`, Cloudflare's *re-challenge non-interactive* count, and it had
climbed to **33**. Every navigation re-presented it, i.e. announced 33 prior
passive failures. iOS never does this: `FAChallengeView` builds its WebView with
`clearCookies: true` and seeds auth cookies only.

Fixing both — a full-size WebView occluded by the opaque app background
(`AndroidRootView`), and expiring the Cloudflare cookie names before each
challenge navigation (`FAWebSession.clearCloudflareCookies`) — took autologin
from never completing to completing on every cold launch tried, feed included.

The two fixes do different jobs, and the counterfactual separates them:

| Viewport | Cookie hygiene | Hidden WebView's own page | Autologin |
|---|---|---|---|
| 1×1 | no | `Un instant…` forever | never |
| full | no | `Un instant…` forever | only via the fallback, slowly |
| 1×1 | yes | `Un instant…` forever | **succeeds** |
| full | yes | real FA index, cleared in place | **succeeds** |

So the cookie hygiene is what makes the app work; the viewport is what lets the
WebView solve a challenge *in place* rather than leaning on the fallback. Note
Cloudflare still decides per request — one of the runs above was challenged on
first contact and recovered through the fallback — so neither fix makes
challenges go away, they make them survivable.

### The control that settles "browser engine vs bare client" (2026-08-12)

The missing control finally ran: take a clearance the WebView earned *after* the
fixes above — one that demonstrably loaded real FA pages — and replay it from the
Mac through plain `curl`, the barest client there is.

| Client | Clearance | Result |
|---|---|---|
| `curl --http1.1 -4`, WebView UA + full cookie header | known-good | **200, 6/6**, ~135 KB, logged in |
| `curl --http1.1 -4`, WebView UA, no cookies | none | 403 `cf-mitigated: challenge` |

**So the bare client was never the problem.** The earlier run in this document —
"Mac curl with identical UA and cookies is refused 403" — is not reproducible with
a *valid* clearance; what it was replaying was a token from a WebView that had
never actually solved a challenge, carried alongside a climbing `cf_chl_rc_ni`.
The discriminator is the token, not the engine. Nothing here argues for a
physical device, a different HTTP stack, or more header tuning.

That also means the WebView-fetch fallback is a backstop rather than the main
road: with a good clearance, `URLSession` is expected to carry page loads.

### One navigation at a time, and when to wipe

Two rules govern the shared engine `FAWebSession` owns.

**All fallback fetches go through `FAWebSession.fetchPageHTML(_:)`.**
`WebViewNavigator.fetchPageHTML` navigates that one engine and then reads the DOM
back out of it, so two at once interleave loads and one fetch returns the other's
page — a *wrong parse*, not merely a slow one. `@MainActor` is no defence: every
`await` inside is a suspension point the other fetch runs at. The gate chains each
fetch behind the previous one, unstructured on purpose so a cancelling caller
advances the queue rather than wedging it, and refreshes the cookie header on the
way out (the navigation that rescued this page may have minted a clearance the
image layer should carry). N concurrent fallbacks become a queue; if that ever
bites, the next lever is per-URL coalescing, not de-serializing.

**`clearCloudflareCookies()` runs before a *retry*, not before the first
navigation.** We reach the fallback because *URLSession* was challenged, which says
nothing about the WebView's own clearance — and dropping it costs every other
request and every image the clearance they were about to replay. Once a navigation
comes back still challenged, the `cf_chl_rc_ni` counter among those cookies is what
the edge escalates on, so the wipe is right from `attempt > 1` on.

Measured over paired cold launches with `cf_clearance` deleted and an uncommitted
`challengeRetries = 1` (so any challenge drops straight to the fallback), same
scroll both times:

| | before | after |
|---|---|---|
| 403 challenge lines | 8 | 1 |
| `asking for resolution` | 5 | 1 |
| `[CFFALLBACK]` lines | 6 | 0 |
| credential pushes | 2 | 1 |

The remaining challenge is the deliberate cold-start deletion. Cloudflare's gate is
probabilistic per request, so one pair carries noise, but 6 → 0 fallbacks is well
outside it. The interleaving the queue prevents was *not* reproducible: across four
forced-challenge runs the emulator never had two fallbacks in flight at once, so
that half lands as a correctness guard rather than a measured fix.

### The challenge escalation path

`CloudflareChallengeCoordinator` is shared with iOS — only its defaults are
per-platform (see the class comment). Android installs its own through
`configure(…)` from `AndroidRootView`, because there is no `UIApplication` and
the cookies live in the WebView's jar rather than `HTTPCookieStorage`.

When `FAHTTPDataSource` exhausts its URLSession retries it now calls
`awaitResolution()` *before* the WebView fetch, because resolution mints a
clearance that fixes every subsequent request, while the fallback only rescues
the one in hand. Then the two stages run:

1. **Passive** — `FAChallengeView` mounts under the opaque background and clears
   the challenge with no visible UI. Measured 1.5–3 s per challenge on the
   emulator, and it is what actually happens: forcing a challenge by deleting
   `cf_clearance` from the jar produced four challenges in one launch, all four
   resolved this way, feed included.
2. **Interactive** — a sheet, entered only when `_cf_chl_opt.cType` reads
   `interactive` or the safety timeout expires. The timeout is 25 s here against
   iOS's 8 s: a managed challenge on the emulator can take 15–20 s, and
   escalating sooner puts a sheet in front of a user it was about to spare.

Two things differ from FAKit's iOS view and are worth knowing:

- **Interaction is detected from `_cf_chl_opt.cType`, not the checkbox's size.**
  FAKit's probe used to measure `iframe[src*="challenges.cloudflare.com"]`, which
  can never match — Turnstile puts that iframe in a *closed* shadow root — and to
  test `window.__cf_chl_opt`, two underscores, where Cloudflare uses one. Both
  platforms now read `cType`. The captured interstitial is a fixture
  (`www.furaffinity.net:cloudflare-managed-challenge.html`) and
  `FAChallengeViewDOMTests` holds the probe's global against it.
- **The stage flags are mirrored into the view's own `@State`.** Reading
  `coordinator.pending` directly recomposes nothing, so `AndroidRootView` keeps
  local `@State` fed by `CloudflareChallengeCoordinator.onStateChange`. The cause
  is import visibility, not cross-module nesting: `CloudflareChallengeCoordinator`
  lives in FAKit, a plain SwiftPM package, so its `@Observable` gets the stdlib
  registrar (see [Every `@Observable` needs `SkipAndroidBridge` in
  scope](#every-observable-needs-skipandroidbridge-in-scope)). Unlike the
  app-module cases, **this one cannot be fixed with an import.** Adding
  `skip-android-bridge` to `FAKit/Package.swift` was tried and reverted: the iOS
  build survives it fine, but the Android compile fails with `missing required
  module 'CJNI'` — `CJNI` is generated by skipstone, which never processes a
  plain SwiftPM package. The mirror stays until FAKit itself is skipstone-built.

#### Escalation must latch, not return

`FAChallengeView.solveChallenge()` polls; it does **not** stop when it escalates.
It used to `return` right after calling `onInteractionRequired()`, which killed
the only thing that could observe the user solving the challenge it had just
escalated to — stage 1 went inert the moment stage 2 appeared, and nothing ever
reported the resolution.

The decision is `FAInterstitial.challengeStep(reachedRealPage:snapshot:elapsed:hasEscalated:)`,
in FAKit so it is testable — the Android app module has no test target. Its
resolution branch sits **above** the `hasEscalated` latch: the latch silences
repeat escalation only, never detection.

Stage 2 passes no `onInteractionRequired` — the sheet *is* the escalation — so it
never probes at all, which also keeps a `_cf_chl_opt` eval every 500 ms off the
sheet's hot path.

Two `FAChallengeView`s are briefly alive while stage 1 unmounts. Both can only
reach `markResolved()` → `complete()`, which is idempotent. Benign.

Still unexercised: the interactive sheet. Cloudflare served only managed
challenges throughout, so stage 2 has never actually drawn, and the
escalate → stay-alive → human-click → resolve sequence is covered by
`FAChallengeViewDOMTests` rather than on-device.

So `fetchPageHTML` no longer hands the interstitial to the parser (which
reported it as a missing element at `FAHomePage.swift:28`, naming a parser line
for a Cloudflare problem). It waits the challenge out in place — reloading
restarts it — retries the navigation, and throws `CloudflareChallengeRequired`
when exhausted. `FAHTTPDataSource` likewise retries `cf-mitigated: challenge`
before paying for a WebView navigation, since the decision is per-request. The
cost when everything is challenged is ~60 s of retries before the error lands
(5 URLSession attempts, then 3 navigations of 8 s polling). That tail is now
useful rather than just slow — the navigations it pays for do clear challenges —
but it is still worth retuning.

One more thing that run turned up: repeated cold launches ANR the app
(`Input dispatching timed out`, main thread blocked ≥15 s) — roughly two thirds
of forced relaunches produced no HTTP request at all and no log past
`updateSession() start`. `establishSession()` is `@MainActor` and awaits
skip-web JNI calls on a WebView that is busy running challenge script. Not
investigated further.

## Followed feed

The feed container is **shared**: `FurAffinity/SubmissionsFeed/SubmissionsFeedView.swift`
is symlinked in, and the old `AndroidSubmissionsFeedView` is gone. Android therefore gets
the refresh badge ("3 new submissions" / "No new submission"), swipe-to-delete, the
cold-launch restore check and foreground autorefresh from the same source as iOS.

The scroll-preserving refresh choreography — a zero-height `fetchTrigger` row whose
`onAppear` performs the fetch, wrapped in a `ScrollViewReader` — **runs on Android too**,
and was measured working on the emulator: the pull fires the trigger, the fetch happens,
the badge shows and fades, and the list holds its position. `ScrollViewReader` inside a
real `body` is fine; the JNI abort under
[§A `ViewModifier` must not defer its `content`](#a-viewmodifier-must-not-defer-its-content)
is specific to a modifier deferring `Content`, which this is not.

`ListItemTracking` **runs on Android too**, from one implementation with no `#if`. It
writes `Defaults[.lastViewedSubmissionID]` as the row crossing 30% from the top scrolls
by — and that value is not a scroll offset: `Model.fetchSubmissionPreviews()` reads it on
the first fetch after launch to build `msg/submissions/new~<sid>@72`, so it is the
server-side pagination anchor. Read depth is restored by *choosing what to fetch*; the
list then renders from its natural top.

It briefly was a no-op here, fenced because `onItemFrameChanged` measured the item in
`coordinateSpace(.named:)`, which SkipUI does not have. The named space was never
needed: the item rect is immediately made list-relative by subtracting a `.global` list
origin, so measuring the item in `.global` too gives the same rect from two APIs Skip
fully implements (`onGeometryChange` → `onGloballyPositionedInRoot`, `frame(in: .global)`
→ `boundsInRoot()`). Measured on the emulator: `boundsInRoot()` is stable for recycled
`LazyColumn` rows, the tracked title follows the 30% line with the same ratios iOS
reports, and after a force-stop the next cold launch fetched `new~<the tracked sid>@72`.

Keep the named coordinate space in mind as its own gotcha: `View.coordinateSpace(.named:)`
is **absent from the SkipSwiftUI façade**, so it fails to compile, while
`GeometryProxy.frame(in: .named(…))` compiles and is **silently wrong** — the name is
bridged across JNI and then discarded, and the call falls into the same branch as
`.local`, returning `CGRect(origin: .zero, size: size)`. Only `.local` and `.global` are
real.

What Android gives up, and why:

| Piece | Status on Android |
|---|---|
| `@Weak var scrollView: UIScrollView?` + `.introspect(.scrollView…)` | Fenced `#if !FA_SKIP_MODULE` — SwiftUIIntrospect isn't a dependency of this module, and the Darwin bridge lacks it too, so `os(Android)` would be the wrong flag. The two reads of it sit behind `waitForPullToSettle()` and `scrollViewIsAtTop` so no `#if` reaches the refresh logic. |
| `waitForPullToSettle()` | Returns immediately. Compose retracts its own indicator, and a blind 1 s sleep would just be a dead second before the fetch. The visible consequence: the pull spinner retracts *before* the fetch finishes (iOS's `refresh(pulled:)` is fire-and-forget) — the badge is the completion feedback. |
| `scrollViewIsAtTop` | Backed by `firstItemIsAtTop`, which `trackFirstItemTop` derives from the first row's clipped `minY` in the `onItemFrameChanged` reports the feed already receives — `> 0` while its top edge is visible, pinned to `0` once it goes under the list. So foreground autorefresh *does* skip on scroll position, as on iOS. |

`.onDelete` **works** on SkipUI, with one difference worth knowing: iOS reveals a Delete
button that must then be tapped, whereas Compose commits the delete at the end of the
swipe with no confirming affordance. A full left-swipe on a card removes that submission
from the FA inbox immediately (`POST /msg/submissions/new~<sid>@<n>`). Be careful
demoing this against a real account.

Holding scroll position across a real *prepend* is now measured too (2026-08-15). The
repro needs no waiting for FA: scroll down a few cards, `am force-stop`, relaunch — the
cold-launch restore fetches `new~<sid>@72`, then the restore check fetches `new@72`, whose
newer items are prepended. Logging every `onItemFrameChanged` callback, the anchor row's
`minY` used to leave the top and take **~5 s** walking back to it (66033206 → 65975822 →
65949461 → 65940282), which is the "moves and then settles" the feed showed. After
[§`withAnimation` marks the whole frame](#withanimation-marks-the-whole-frame-process-wide)
it is one transient frame: the prepended head shows for **30–50 ms**, then the anchor is
back at `minY≈10` and stays. On screen that is a single frame of placeholder rows before
the list is where it was, with the new rows above it and the badge showing.

Still not verified, for want of the state to verify it against: the empty feed, which is
unreachable through the offline session.

### `withAnimation` marks the whole frame, process-wide

On iOS a `withAnimation` transaction reaches only the state written inside it. On SkipUI it
sets a **static** marker (`Animation.recentWithAnimationAnimation`) cleared only on the next
Compose frame, and `Animation.current` / `Animation.isInWithAnimation` fall back to it. So
*any* state write animates *every* view that recomposes in that frame. For a `List` that
means two things (`skip-ui/…/List.swift`): rows compose with `Modifier.animateItem()`, so a
prepend animates row placement, and `ScrollToIDAction` uses `animateScrollToItem` instead of
`scrollToItem`, so a `ScrollViewProxy.scrollTo` becomes an animated scroll.

That is what made the feed slide: `fetchSubmissionPreviews()` ended with
`withAnimation { newSubmissionsCount = … }` in the same main-thread turn as the prepend and
the choreography's `scrollTo`. **Prefer `.animation(_:value:)`**, which sets
`EnvironmentValues._animation` for one subtree and never touches the marker.

Two callers had to change, and the second one is the lesson: `FAImage` faded a freshly
loaded image in with `withAnimation`, so *every thumbnail arrival* marked a frame. Removing
only the feed's call cut the excursion from ~5 s to ~460 ms; the rest went away only when
the image fade became scoped too. Anything on a hot path — image loads, list rows, badges —
must not use the global form.

`.transition(…)` is not a substitute: SkipUI resolves transitions in the *container*
(`VStack.swift`, via `Animation.current(isAnimating:)`, evaluated before it recurses into the
child's own modifiers), so it only ever sees an ambient animation set above the container or
the global mark. A scoped `.animation(_:value:)` on the transitioning view cannot reach it —
which is why the refresh badge briefly lost its animation on Android.

**State-driven properties do animate from a scoped animation**, because `.opacity`,
`.offset` and `.scaleEffect` each read `EnvironmentValues._animation` themselves
(`AdditionalViewModifiers.swift` → `Animatable.asAnimatable`). Since the animation-resume
patch (see [Why skip-ui / skip-fuse-ui are forked](#why-skip-ui--skip-fuse-ui-are-forked))
that also holds across recycling: an animation interrupted by a `List` row leaving the
composed window resumes at the right point instead of dying at its end state.
`NotificationOverlay` is the worked example: it stays mounted and moves through a
`hidden → shown → fading → hidden`
phase with `.opacity`/`.offset` and `.animation(_:value:)`, which reproduces `fallAndFade` —
including its asymmetry, since fading holds the offset at 0 — on both platforms.

**Key `.animation(_:value:)` on a value Kotlin can compare.** SkipUI installs the animation
only on the composition where `value` differs from the remembered one
(`Animation.swift`, `isValueChange`); everywhere else the property snaps. Keying it on a
**Swift enum** (`value: phase`) silently never fires — the pill jumped from absent to fully
placed within one 33 ms frame, measured on a 30 fps capture — while `value: phase == .shown`
animates. Keep such keys to bridged primitives (`Bool`, `Int`, `String`), and prove any new
animation on the emulator with a deliberately slow duration first: at 0.35 s the difference
between "animating" and "snapping" is 10 frames, and easy to miss.

## Submission screen

Tapping a feed card pushes the same `RemoteSubmissionView` → `SubmissionView` the iOS app
draws. Those, and `RemoteView`, `SubmissionPreviewView`, `SubmissionControlsView`,
`SubmissionMetadataView` and all of `Comments/`, are symlinked **verbatim**.

Ported: the image, the zoomable full-screen viewer, favorite (with the optimistic
`UpdateHandler` rollback), Save to gallery, Share, the description with in-app link
routing, read-only threaded comments including the deep-linked one's highlight pulse,
and the metadata screen.

Deferred, with the reason:

| Not ported | Why |
|---|---|
| Comment posting, note sending | The `CommentEditor`/`NoteEditor` UI isn't ported. Android passes `replyAction: nil` / `acceptsNewReplies: false`, so the swipe/context reply paths are inert. (`Replying`'s storage is now `@Observable`, not `ObservableObject`, so the machinery around the editors is no longer the blocker.) |
| Story (`.text`) and music (`.audio`) submissions | `StoryDocument` (PDFKit reflow, DOCX, QuickLook) and AVPlayer + `MPNowPlayingInfoCenter` are Apple-only stacks. Both render a placeholder with a link to the file. |
| `scrollToItem` (scroll a deep-linked comment into view) | see below |

### Android-only substitutes

Each keeps the iOS name and signature so symlinked callers compile unchanged:
`SubmissionMainImage` (the iOS one is written against Kingfisher's `KFImageProtocol`),
`HTMLView`, `Zoomable`, `FlowLayout`, `MediaSaveHandler`,
`RemoteContentToolbarItem`, `SubmissionTextContent`/`SubmissionAudioContent`, and the
no-ops in `SubmissionShims.swift`.

`HTMLView` is the one that does real work rather than standing in. iOS renders FA's rich
text through WebKit's HTML importer into a `UITextView`; here `FAKit` normalises the
markup (`FAHTMLNormalizer`) and Compose parses it — see `Text(html:)` under
[the other fork patches](#the-other-fork-patches). The view itself only puts back what
that parser drops: a `Divider()` where each `<hr>` was, and an inline view at each
`<img>`'s U+FFFC. Accepted losses, none of which FA's corpus exercises: `<ol>` numbering
degrades to bullets, `<blockquote>` loses its indent and bar, `<code>`/`<pre>` lose
monospace, absolute px font sizes are ignored, and `<sub>` gets a baseline shift without
the size reduction. Headings come out at Compose's `RelativeSizeSpan` steps rather than
FA's exact pixel sizes. The one iOS feature not reachable is animated GIF avatars, which
stay on their first frame.

Its padding is 3 dp vertical but **8 dp horizontal**, which looks asymmetric and is not.
The iOS view sets `textContainerInset = 3` on all edges, but a `UITextView` also keeps
its default `textContainer.lineFragmentPadding = 5` on the leading and trailing edges,
and `makeUIView` never zeroes it — so iOS insets text by 8 pt horizontally and 3 pt
vertically. Copying only the inset left Android's text half as far from the edge. One
fix covers two places: the submission description and every comment bubble
(`CommentView`'s `textBubble`) go through this view.

`InAppLinkConversion.swift` duplicates ~20 lines of `InAppNavigation.swift` — the
link-rewriting half. Splitting the iOS file instead would mean an `.xcodeproj` edit, so
this is a knowing duplication: **keep the two in sync.** The other half, `view(for:)`,
can't be shared at all (it names screens that don't exist here) and lives in
`AndroidNavigationDestination.swift`.

### A `ViewModifier` must not defer its `content`

`ViewModifier.Content` reaches Swift as a `JavaBackedView` around a JNI **local**
reference, valid only for the frame that built the modifier. Using it synchronously is
fine; capturing it in a closure Compose invokes later aborts the process:

```
JNI DETECTED ERROR IN APPLICATION: jobject is an invalid JNI transition frame reference
  from kotlin.Pair skip.bridge.SwiftBackedFunction1.Swift_invoke(long, java.lang.Object)
```

That is what `ScrollToItemModifier` does — `ScrollViewReader { reader in content.onFirstAppear { … } }`
— so `scrollToItem` is an Android no-op. In a tombstone, look for
`SwiftBackedFunction*.invoke` directly under the SkipUI container owning the closure.

### Save and Share

`FAMediaBridge.kt` (app module, reached by name through `AnyDynamicObject` like
`FACoilBridge`) inserts into MediaStore's `Pictures/FurAffinity` and starts
`ACTION_SEND`. Two things the manifest must carry, both easy to lose in a regeneration:

- `<provider android:name="androidx.core.content.FileProvider">` with
  `${applicationId}.fileprovider` and `@xml/file_paths`. Shared files sit in the app
  cache, which no other app may read, so they go out as `content://` URIs.
- `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="28"` — the MediaStore insert needs no
  permission under scoped storage, but does on API ≤28.

`FAImageStore.namedFileUrl(for:)` stages the bytes under the media URL's own filename
first: the coil cache names entries by content hash with **no extension**, so saving or
sharing straight out of it yields a nameless file with no detectable MIME type.

`FileManager.default.temporaryDirectory` is safe to share from and needs no platform
branch: the Android build of corelibs Foundation resolves it through `XDG_CACHE_HOME`
(that string is in `libFoundation.so`; `/tmp` and `TMPDIR` are not), and
`AndroidBridgeBootstrap` points that at `context.cacheDir`. So the exported log
(`generateLogFile` in `Logs.swift`) already lands inside the app cache `@xml/file_paths`
exposes — no `/tmp` involved.

## Rules for shared sources

<a name="every-observable-needs-skipandroidbridge-in-scope"></a>

An *unguarded* file under `FurAffinity/` is compiled **twice more** than the iOS target
compiles it: once for Android (`os(Android)` true) and once for the module's Darwin
bridge (`os(Android)` **false**, UIKit importable). Both compiles see only this module —
never the iOS app target — so:

- Guard anything that exists only in the Xcode target (SwiftUI `#Preview`s and their
  demo data) with `#if !FA_SKIP_MODULE`. That flag is defined by `Package.swift` for
  both Skip compiles; `os(Android)` cannot express it.
- Guard Darwin-only frameworks and APIs (Kingfisher, Liquid Glass, `UIKit` types) with
  `#if !os(Android)` / `#if canImport(…)`; those are genuinely per-platform. Reach for
  it last, though — `Model.swift` was fenced twice and now carries no conditional at
  all: `Defaults.updates` got an Android implementation (see [Defaults](#defaults)) and
  the `willEnterForegroundNotification` loop became `ForegroundAutorefresh`, a shared
  `scenePhase` modifier. Skip marks that notification unavailable on both layers and
  points at `ScenePhase`, which on Android reads a Compose state fed by the Activity
  lifecycle.
- **An Android substitution file must not be `#if os(Android)`-guarded.** When a
  shared file calls one name that resolves per platform (`ImageCacheControl`,
  `clearLoginCookies`, `share`), the Android declaration lives in an `Android/`
  directory while its `iOS/` twin is guarded out. `os(Android)` is false for the Darwin
  bridge compile, so a file-level guard there leaves shared callers with *no*
  declaration at all. Leave the file unguarded and put `#if canImport(Android)`
  around the JNI inside, with a Darwin no-op — the way `CoilImageLoader` does. This
  fails quietly: `skip android build` and the APK are both green, and only
  `skip app launch --android` (which builds the bridge) reports it.
  The exception is a name a *package* already declares on Darwin: `Helpers/Android/AndroidDefault.swift`
  is `#if os(Android)`-guarded precisely because the bridge compile resolves `Default`
  from the real Defaults package, and an unguarded declaration would collide.
- **`import os` needs no guard.** Android's Swift SDK has no `os` module, so FAKit
  ships one: a target literally named `os` (`FAKit/Sources/OSCompat/`) that re-exports
  `AndroidLogging`'s `Logger` and vends a no-op `OSSignposter`. It is only ever a
  dependency `.when(platforms: [.android])`, so Darwin still resolves the system
  module. Only `Logger` + the `OSSignposter` subset FAKit/FAPages use are covered —
  anything else from `os` (e.g. `OSAllocatedUnfairLock`) still needs a guard, or an
  addition to the shim.
- **Every `@Observable` compiled for Android must have `SkipAndroidBridge` in
  scope in its own file** — in practice `import SwiftUI`, never `import
  Observation` on its own.

  The macro expands to `Observation.ObservationRegistrar`, and that name resolves
  two ways. `SkipAndroidBridge` vends a `public struct Observation` whose nested
  registrar hops through JNI to Compose's `MutableStateBacking`; the real
  `Observation` *module* vends the stdlib one, which knows nothing about Compose.
  The struct shadows the module, but only where `SkipAndroidBridge` is imported —
  and `SkipSwiftUI/Fuse/Observation.swift` does `@_exported import
  SkipAndroidBridge`, which is why a plain `import SwiftUI` suffices and why most
  `@Observable`s here work by accident of that import.

  The symptom is the nastiest kind: compiles clean, mutates correctly, and the
  view simply never re-renders. No error, no warning. `AppInformation` (the update
  badge and Settings' version row) and `MediaSaveHandler+Android` (the Save
  checkmark and its haptic) were both silently inert this way.

  To check which registrar a file got, demangle its undefined symbols:

```
nm -u .build/Darwin/DerivedData/Build/Intermediates.noindex/BuildToolPluginIntermediates/\
<worktree>.output/FurAffinityUI/skipstone/FurAffinityUI/build/swift/\
aarch64-unknown-linux-android28/debug/FurAffinityUI.build/<File>.swift.o \
  | swift demangle | grep ObservationRegistrar
```

  `SkipAndroidBridge.Observation.ObservationRegistrar` is bridged;
  a bare `Observation.ObservationRegistrar` is inert. Grep the Android-built tree
  for `^import Observation` — each hit is a silent non-recomposition waiting to
  happen.

  This does **not** reach FAKit. A plain SwiftPM package cannot depend on
  `SkipAndroidBridge`: it drags in `skip-bridge`, whose `CJNI` module is generated
  by skipstone and unresolvable outside it. FAKit's `@Observable`s therefore still
  need mirroring into a view's `@State` — see the Cloudflare stage flags in
  `AndroidRootView`.

- `#if` blocks must contain balanced braces — split an `if/else` into two whole
  branches rather than fencing one arm.
- `@State`/`@Environment` on a bridged view must be **internal**, not `private`, and so
  must a `ViewModifier` struct itself. Same for a *generic* `ViewModifier`: skipstone's
  generated bridge calls its `body` without the `content:` label, so type-erase the
  generic parameter instead (see `ScrollToItemModifier`).
- **State property wrappers are matched by attribute name.** skipstone emits a
  bridged view's `Java_initState_<name>`/`Java_syncState_<name>` from the literal
  attribute (`@State`, `@AppStorage`, …). A wrapper of your own gets no entry, so its
  box is never given a Compose state and the value neither persists nor recomposes —
  silently. Wrapping `AppStorage`, or `typealias Default = AppStorage`, does not help,
  and skipstone is a closed binary (the `skip` Homebrew cask), so the list can't be
  extended. To check whether a property got bridged, grep the generated bridge:

```
grep Java_initState_ .build/plugins/outputs/*/FurAffinityUI/destination/skipstone/SkipBridgeGenerated/<View>_Bridge.swift
```

  A custom wrapper can still work if it **owns its own box** instead of relying on
  that codegen — see `FurAffinity/Helpers/Android/AndroidDefault.swift`, which backs `@Default` on
  Android. `BridgedAppStorageBox`, `Java_initStateSupport()` and
  `Binding(appStorageBox:)` are public skip-fuse-ui API, and the generated
  `rememberSaveable` only supplies *lifetime*: one support object kept alive across
  recompositions. A static box per key gives the same guarantee for process-lived app
  settings, and reading it during body evaluation still reads the Compose
  `MutableState` inside the composition, which is what registers the recomposition
  dependency. This does **not** generalize to per-view-instance state.
- **`@State` inside `#if DEBUG` never recomposes.** Skipstone skips those blocks when it
  generates `<View>_Bridge.swift`, so the property gets no `StateSupport`: writes land in
  the box and the view never redraws, silently. Declare it outside the guard. To check a
  view, `grep Java_initState_ $(find .build -name "<View>_Bridge.swift")`.
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
- **Don't call `withAnimation` from shared code.** On SkipUI it marks the entire next
  Compose frame process-wide, so an unrelated `List` recomposing in that frame animates
  its rows and turns its `scrollTo` into an animated scroll. Use `.animation(_:value:)`,
  which is scoped to a subtree. See
  [§`withAnimation` marks the whole frame](#withanimation-marks-the-whole-frame-process-wide).

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
