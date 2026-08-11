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
instead of erroring. After changing a catalog, confirm the entry actually landed
(the mirrored tree is itself made of symlinks, so `find -type f` won't list them):

```
ls -R .build/plugins/outputs/*/FurAffinityUI/destination/skipstone/FurAffinityUI/src/main/assets
```

The path segment after `outputs/` is the **checkout directory's name**, not the word
`android` — it differs per worktree, hence the glob.

### Generated art

An entry big enough that a second copy in git would hurt is generated from the iOS
art instead, and git-ignored. `Scripts/generate-android-assets.sh` writes two sets:

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
Scripts/generate-android-assets.sh
```

A SwiftPM prebuild plugin would be nicer, but it cannot work: `Image(_:bundle:)`
resolves through this module's catalog **in the source tree**, and the plugin
sandbox forbids writing there.

## Prerequisites

```
skip checkup                     # verifies toolchain (Xcode, Android SDK, Gradle, JDK)
skip android sdk install         # if the Android SDK/NDK is missing
Scripts/generate-android-assets.sh   # derived art (see Generated art above)
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

## Defaults

`UserDefaults.standard` means two different things on Android. In a module Skip's
transpiler processes, skipstone emits `typealias UserDefaults = AndroidUserDefaults`,
so `.standard` is the app's `SharedPreferences` (`shared_prefs/defaults.xml`) — where
`@AppStorage` and raw `UserDefaults` writes land. `Defaults` is a plain SwiftPM
dependency compiled untouched, so *its* `.standard` is Foundation's own instance: a
separate store nothing else reads, and one that never reaches disk here.

That is why `Defaults[key] = value` used to vanish silently while reads returned the
new value — both ends were talking to the orphan store. The fork exposes
`Defaults.defaultSuite` for it, and `FurAffinityUI/AndroidDefaultsSuite.swift` assigns
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
module re-declares the wrapper over `@AppStorage` in `FurAffinityUI/AndroidDefault.swift`.
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
| `Ceylo/skip-ui` | `listRowInsets`; `Text(bridgedMarkdown:)`; `FlowRow`; SF Symbol mappings |
| `Ceylo/skip-fuse-ui` | the Fuse side of each: `listRowInsets`, `Text(AttributedString)`, `FlowRow`, plus `glassEffect`/`AnyTransition.animation` un-`unavailable`d |

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

### The other fork patches

- **`Text(AttributedString)`** is `@available(*, unavailable)` upstream, which blocks all
  rich text. SkipUI's rich-text model *is* markdown (an `AttributedString` renders
  through its `MarkdownNode`), so the Fuse side re-emits attributed content as escaped
  markdown — `[text](<url>)` for links, `**`/`*`/`~` for inline presentation intents —
  and `SkipUI.Text(bridgedMarkdown:)` parses it. That init deliberately bypasses
  `LocalizedStringKey`: the content is user data and must not be bundle-looked-up or
  `String.format`ed. `markdownRepresentation` returns nil when nothing needs markdown and
  `Text` then falls back to `verbatim`, because SkipUI only builds a `MarkdownNode` when
  the string actually contains a link or emphasis construct and renders the source
  verbatim otherwise — which would expose the escapes.
- **`FlowRow`** replaces SwiftUI's `Layout` protocol, which SkipUI doesn't implement and
  which can't be emulated: a `Layout` enumerates and places its subviews, and an opaque
  `Content` gives a Fuse module no access to them. Compose wraps natively, so it is a
  container instead, with `FurAffinityUI/FlowLayout.swift` keeping the iOS call signature.
- **`glassEffect`** and **`AnyTransition.animation`** become pass-throughs rather than
  `unavailable`. `#available(iOS 26, *)` is vacuously true off-Apple, so a shared source
  takes its Liquid Glass branch on Android; making the call unbuildable is worse than
  ignoring an effect Compose can't express.
- **SF Symbol mappings** for the symbols this app uses (`safari`,
  `square.and.arrow.down`, `bubble`, `exclamationmark.bubble`, `ellipsis.bubble`,
  `message`, `text.badge.star`). Unmapped names render as a warning triangle.

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

`FurAffinityUI/FALoginView.swift` is the Android substitute for FAKit's WebKit one,
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

## Submission screen

Tapping a feed card pushes the same `RemoteSubmissionView` → `SubmissionView` the iOS app
draws. Those, and `RemoteView`, `SubmissionPreviewView`, `SubmissionControlsView`,
`SubmissionMetadataView` and all of `Comments/`, are symlinked **verbatim**.

Ported: the image, the zoomable full-screen viewer, favorite (with the optimistic
`UpdateHandler` rollback), Save to gallery, Share, the description with in-app link
routing, read-only threaded comments, and the metadata screen.

Deferred, with the reason:

| Not ported | Why |
|---|---|
| Comment posting, note sending | The `CommentEditor`/`NoteEditor` UI isn't ported. Android passes `replyAction: nil` / `acceptsNewReplies: false`, so the swipe/context reply paths are inert. (`Replying`'s storage is now `@Observable`, not `ObservableObject`, so the machinery around the editors is no longer the blocker.) |
| Story (`.text`) and music (`.audio`) submissions | `StoryDocument` (PDFKit reflow, DOCX, QuickLook) and AVPlayer + `MPNowPlayingInfoCenter` are Apple-only stacks. Both render a placeholder with a link to the file. |
| `scrollToItem` (scroll a deep-linked comment into view) | see below |

### Android-only substitutes

Each keeps the iOS name and signature so symlinked callers compile unchanged:
`SubmissionMainImage` (the iOS one is written against Kingfisher's `KFImageProtocol`),
`HTMLView`, `Zoomable`, `UserNameView`, `FlowLayout`, `MediaSaveHandler`,
`RemoteContentToolbarItem`, `SubmissionTextContent`/`SubmissionAudioContent`, and the
no-ops in `SubmissionShims.swift`.

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

A file under `FurAffinityUI/Shared/` is compiled **twice more** than the iOS target
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
  `clearLoginCookies`, `share`), the Android declaration lives in `FurAffinityUI/`
  while the iOS one stays out of this module. `os(Android)` is false for the Darwin
  bridge compile, so a file-level guard there leaves shared callers with *no*
  declaration at all. Leave the file unguarded and put `#if canImport(Android)`
  around the JNI inside, with a Darwin no-op — the way `CoilImageLoader` does. This
  fails quietly: `skip android build` and the APK are both green, and only
  `skip app launch --android` (which builds the bridge) reports it.
  The exception is a name a *package* already declares on Darwin: `AndroidDefault.swift`
  is `#if os(Android)`-guarded precisely because the bridge compile resolves `Default`
  from the real Defaults package, and an unguarded declaration would collide.
- **`import os` needs no guard.** Android's Swift SDK has no `os` module, so FAKit
  ships one: a target literally named `os` (`FAKit/Sources/OSCompat/`) that re-exports
  `AndroidLogging`'s `Logger` and vends a no-op `OSSignposter`. It is only ever a
  dependency `.when(platforms: [.android])`, so Darwin still resolves the system
  module. Only `Logger` + the `OSSignposter` subset FAKit/FAPages use are covered —
  anything else from `os` (e.g. `OSAllocatedUnfairLock`) still needs a guard, or an
  addition to the shim.
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
  that codegen — see `FurAffinityUI/AndroidDefault.swift`, which backs `@Default` on
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
