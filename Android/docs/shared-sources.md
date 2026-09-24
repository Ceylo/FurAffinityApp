# Shared sources

## Why everything unported is guarded

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

## Basenames must be unique across the tree

SwiftPM derives one object file per source *basename*, and skipstone one
`<Name>_Bridge.swift`, both flattened into a single directory. Two files with the
same name anywhere in the target fail the build:

```
error: couldn't build …/SkipBridgeGenerated/Zoomable_Bridge.swift
       because of multiple producers: Skip FurAffinityUI, Skip FurAffinityUI
```

This bites the `iOS/`+`Android/` substitution pairs, and a guard does not help —
the guarded file still *emits* a same-named (empty) bridge. Hence the
`…+Android.swift` files; the directory still carries the platform meaning, the
suffix only keeps the name unique.

**The rule spans FAKit too**, which carries the plugin as well (see
[Rules for shared sources](#rules-for-shared-sources)) — hence the suffix on
`FALoginView+Android.swift` and `FAChallengeView+Android.swift`, but not on
`FAWebSession.swift`/`FAWebView.swift`, which have no twin.

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
adb shell run-as com.example.id1234.<worktree> cat shared_prefs/defaults.xml
```

(a debug build's applicationId carries the worktree suffix — see
[Run](build-and-run.md#run))

## One module, one image

A module that holds process-global state must be defined by **exactly one** `.so` in
the APK, or every consumer gets its own copy of every global and they never see each
other's writes. This is the linkage sibling of [Defaults](#defaults) above — the same
class of bug, arrived at from the other direction.

SwiftPM decides that per *edge*. A **cross-package product** is linked dynamically: one
image, everyone imports it. A **target dependency inside the same package** is linked
*statically into each product of that package*, even when the product is `.dynamic`.

That is what happened to `FALogging`. It was a target inside `FAKit`, and `FAKit`'s two
products both depended on it by target name, so `libFAKit.so` and `libFAPages.so` each
absorbed a private copy alongside the real `libFALogging.so`. Only `FurAffinityUI`, a
different package, linked it correctly. Three copies of `FALogSubsystem.override` meant
the Kotlin bridge's write at startup reached one of them (the wrong logcat tag was the
cosmetic half), and three copies of `PersistentLogStore.shared` meant three positional
`FileHandle`s writing `files/Logs/app.log` at three independent offsets — lines
truncated mid-word and overwritten, in the file the user exports from Settings and
sends us to diagnose a bug. Rotation would have been worse: three `currentSize` counters
against one cap, and the first to rotate leaves the other two writing an unlinked inode.

The fix is structural, not a logic change: `FALogging` is its own package at the repo
root, so `FAKit` and `FAPages` reach it — and `OSCompat`, which moved with it, a
cross-package *target* dependency being impossible — as products. **The `.dynamic`
rewrite under `SKIP_BRIDGE` is the load-bearing half** and the new manifest carries its
own copy: with an automatic (static) product no `libFALogging.so` is produced at all and
both consumers define their own again.

None of this is visible from Swift. An `assert(FALogSubsystem.identifier == …)` in
`onInit()` **passes** while FAKit still reads nil, because both sides of the comparison
bind to the app module's copy — the same *never trust a read-back* caution as
[Defaults](#defaults). Only the symbol tables tell the truth, so the check is a
build-time one:

```
Scripts/Android/check-shared-globals.sh [debug|release]
```

It counts, per image, the defined `OBJECT` symbols mangled into each listed module
(`$s9FALogging…`) and fails naming every extra definer and the `vpZ` static storage it
duplicates. `Scripts/Android/run.sh` runs it after the Gradle build. Its module list is
the modules that own mutable process-global state *and* are consumed by more than one
image; add to it when a module grows some. `FAPages` is deliberately not on it: it is
absorbed by `libFAKit.so` too, but everything it defines is an immutable `let`, so the
copies are indistinguishable.

### What the split costs the Xcode project

The iOS app is not built by SwiftPM, and Xcode is stricter about local packages than
`xcodebuild` is. Two constraints fell out of making FALogging its own package, and they
pull against each other:

- **A package that is already another package's path dependency does not become a
  workspace root on its own.** `FAKit` is registered by its plain folder reference in
  `project.pbxproj`; `FALogging` cannot be, because `FAKit` reaches it as
  `.package(path: "../FALogging")` first. Xcode then builds its targets but exposes
  none of its *products*, and every target that links one fails with
  `Missing package product 'FALogging'` / `'OSCompat'` — while `xcodebuild` resolves
  the same tree happily. The fix is an explicit `XCLocalSwiftPackageReference`
  (`relativePath = FALogging`) in `packageReferences`, which needs
  `objectVersion = 60` / `compatibilityVersion = "Xcode 14.0"`. **FALogging must have
  no folder `PBXFileReference`**: with both, Xcode goes back to failing.
- **Dropping that folder reference costs the scheme its container.** A testable's
  `ReferencedContainer = "container:<dir>"` resolves through the folder reference, not
  through the package reference, so `FALoggingTests` was silently skipped — no error,
  just fifteen tests gone from the run. So the test target is declared in
  `FAKit/Package.swift` over sources in `FAKit/Tests/FALoggingTests/`, depending on the
  `FALogging` product, and the scheme keeps `container:FAKit`.

Check the count, not just the exit status: a dropped testable does not fail the build.
The suite is **346** cases — 78 FurAffinityTests, 213 FAKitTests, 40 FAPagesTests,
15 FALoggingTests.

## Rules for shared sources

<a name="every-observable-needs-skipandroidbridge-in-scope"></a>

**Two modules carry the skipstone plugin, not one.** FAKit joined FurAffinityUI so it
could own the Android web layer — only a plugin-carrying module gets the Kotlin glue a
bridged view's `@State` needs. Everything below applies to `FAKit/Sources/FAKit/` too,
with one difference: FAKit's `FA_SKIP_MODULE` is gated on `SKIP_BRIDGE`, which the
Darwin bridge pass does not set, so there FAKit compiles exactly as in Xcode. Cost on
the iOS side: 37 MB Release instead of 27, 11 embedded frameworks instead of 1.

An *unguarded* file under `FurAffinity/` is compiled **twice more** than the iOS target
compiles it: once for Android (`os(Android)` true) and once for the module's Darwin
bridge (`os(Android)` **false**, UIKit importable). Both compiles see only this module —
never the iOS app target — so:

- Guard anything that exists only in the Xcode target with `#if !FA_SKIP_MODULE`. That
  flag is defined by `Package.swift` for both Skip compiles; `os(Android)` cannot
  express it.
- Leave `#Preview`s unguarded. On Android `#Preview` and `@Previewable` come from the
  skip-fuse-ui fork's `SwiftUI` shim and expand to nothing, but the preview body is
  still type-checked — so a preview that goes stale fails the Android build too. A
  preview that calls API SkipSwiftUI lacks (`GlassEffectContainer`, `.tertiary`)
  keeps its guard, with a comment naming the API.
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
  around the JNI inside, with a Darwin no-op — the way `ImageFetchBridge` does. This
  fails quietly: `skip android build` and the APK are both green, and only
  `skip app launch --android` (which builds the bridge) reports it.
  The exception is a name a *package* already declares on Darwin: `Helpers/Android/AndroidDefault.swift`
  is `#if os(Android)`-guarded precisely because the bridge compile resolves `Default`
  from the real Defaults package, and an unguarded declaration would collide.

  **The rule follows the callers into FAKit.** `Android/FAHTTPDataSource.swift`,
  `FAWebSession.swift` and `FAWebView.swift` are unguarded because the unguarded
  `AndroidRootView` and `LoginCookies+Android` name them, so the bridge compile needs
  the declarations for `arm64-apple-ios` — and so, therefore, does the iOS app, which
  is the price of the arrangement. Only `iOS/` files whose *frameworks* are Darwin-only
  (UIKit, WebKit, PDFKit, Cache) can be guarded on the platform.

  A **third** case, beside the app-module `AndroidDefault` exception: when the Darwin
  twin is in *this same module*. `FALoginView+Android.swift` and
  `FAChallengeView+Android.swift` would redeclare their `iOS/` twins unguarded, so they
  take `#if os(Android)` against the twin's `#if !os(Android)`. That is safe for a
  *bridged* view because **skipstone evaluates `os(Android)` as true**: this half still
  gets its full `<Name>_Bridge.swift`, the twin's comes out empty. Check that after any
  change — an empty bridge is the silent kind of breakage (renders once, never
  recomposes):

  ```
  .build/plugins/outputs/<worktree>/FurAffinityUI/destination/skipstone/FurAffinityUI/\
  build/swift/plugins/outputs/fakit/FAKit/destination/skipstone/SkipBridgeGenerated/
  ```
- **`import os` needs `#if canImport(os)`.** Android's Swift SDK has no `os`
  module, so the `FALogging` package ships `OSCompat`
  (`FALogging/Sources/OSCompat/`), which re-exports `AndroidLogging`'s `Logger` and
  vends an ATrace-backed `OSSignposter`. It is a dependency
  only `.when(platforms: [.android])`, so Darwin still resolves the system module,
  and the three call sites pick between them:

  ```swift
  #if canImport(os)
  import os
  #else
  import OSCompat
  #endif
  ```

  It must **not** be named `os` — see
  [Module-name poisoning](build-and-run.md#module-name-poisoning) item 1. Only
  `Logger` + the `OSSignposter` subset FAKit/FAPages use are covered — anything
  else from `os` (e.g. `OSAllocatedUnfairLock`) still needs a guard, or an
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
  `SubmissionControlsView` never saw `saveHandler.state` change, so the checkmark,
  its `onChange` and its `.sensoryFeedback` all stayed silent while the handler
  logged `.inProgress → .succeeded → .idle` on time (measured 2026-08-22 — one
  import swap restored all three together).

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

  **This reaches FAKit too, since it became a skipstone module** — with `SkipFuseUI`
  in its Android closure the same import applies, spelled `#if os(Android) import
  SwiftUI #else import Observation #endif` because FAKit gates SwiftUI on the platform
  (`CloudflareChallengeCoordinator`). Here skipstone does warn, unlike the app-module
  cases:

  ```
  warning: This file contains @Observables, but they will not be able to power your
  Android UI unless you 'import SkipFuse' or 'import SkipFuseUI'
  ```

  Adding `skip-android-bridge` on its own instead fails the Android build on `missing
  required module 'CJNI'` — a missing dependency edge, **not** the plugin story once
  told here (`CJNI` is a plain C target in `swift-jni`, whose modulemap SwiftPM hands
  to any target that declares a path to it). The plugin brings the whole closure, and
  the mirror `AndroidRootView` kept for the Cloudflare stage flags is gone.

  Same name-resolution family as [Module-name poisoning](build-and-run.md#module-name-poisoning),
  inverted: there a module shadowed what a target wanted, here a type must shadow
  a module and fails to when unimported.

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
  [§`withAnimation` marks the whole frame](screens.md#withanimation-marks-the-whole-frame-process-wide).
- **An armed animation poisons every per-frame write in the same subtree.** `.offset`
  and `.scaleEffect` don't set a Compose value, they route it through `toAnimatable`
  (`Animation.swift`), which parks it in an `Animatable` and re-launches `animateTo` on
  every write while an animation is armed — so a gesture writing 60 times a second eases
  from a standstill toward a target the finger keeps moving. `withAnimation` (previous
  bullet) is what arms it, and the `Animatable`'s resume record is `rememberSaveable`, so
  an interrupted animation's start value outlives a sheet dismissal and the next
  presentation's first frames render from it. Use `.animation(_:value:)` on a value
  **set once** — a counter bumped by the action — which arms only the composition where
  it changes.
- **To animate a value a gesture also writes, step it yourself.** `.animation(_:value:)`
  is no use for the reason above, and it leaves the property already *at* its target, so
  an animation in flight can't be caught and continued — most of what inertia means.
  `Zoomable+Android`'s `runMotion` is the shape. Nothing in the SkipSwiftUI surface
  aligns work to a frame — `TimelineView` exists in skip-ui but has no SkipSwiftUI
  counterpart, and `withFrameNanos` is reachable only from skip-ui's own Kotlin — so it
  over-ticks at 4 ms instead, which Compose absorbs: snapshot writes apply immediately
  but recomposition happens at frame time, and the per-tick cost is a JNI state write,
  not a layout pass. Measured on a 60 Hz AVD against Compose's own frame-clock-driven
  animation as the control, a stepped fling held one distinct frame per vsync — 16 frames
  at 61 fps with zero duplicates, against the control's 21 at 63 fps with zero.
  (Duplicates do appear in the last 40 ms, where the spline's own velocity is under a
  pixel per frame; Android's `OverScroller` tail is the same. Nothing here speaks to
  90/120 Hz panels.) A hand-stepped loop needs a hand-written stop, too: a `Task`
  outlives the composition that started it, where a Compose animation dies with it, so
  the view has to cancel from `onDisappear` or a fling launched just before a sheet
  dismissal keeps ticking against nothing.
- **SkipUI's `.offset` is Compose's *layout* offset**, not a draw-time translation, so
  the moved node is still clipped to the rect it had before the offset. Content that must
  survive being pushed past its own bounds has to be sized to the viewport first, or —
  as in `Zoomable+Android` — kept to a bounded offset.
- **A bridged `@State` survives a sheet dismissal.** Skipstone backs it with
  `rememberSaveable`, which saves on disposal and restores at the same key, so
  re-presenting a sheet hands the content whatever the last presentation left behind.
  Presented content has to reset itself — `Zoomable+Android` does it from `onAppear`
  (a plain `remember`, so that one *does* re-run) and again from the fresh viewport
  measurement, since the sheet is remeasured 24 pt shorter as it dismisses.
