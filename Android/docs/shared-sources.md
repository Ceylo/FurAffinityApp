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
the guarded file still *emits* a same-named (empty) bridge. Hence the eleven
`…+Android.swift` files; the directory still carries the platform meaning, the
suffix only keeps the name unique.

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
- **`import os` needs `#if canImport(os)`.** Android's Swift SDK has no `os`
  module, so FAKit ships `OSCompat` (`FAKit/Sources/OSCompat/`), which re-exports
  `AndroidLogging`'s `Logger` and vends a no-op `OSSignposter`. It is a dependency
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

  This does **not** reach FAKit. A plain SwiftPM package cannot depend on
  `SkipAndroidBridge`: it drags in `skip-bridge`, whose `CJNI` module is generated
  by skipstone and unresolvable outside it. FAKit's `@Observable`s therefore still
  need mirroring into a view's `@State` — see the Cloudflare stage flags in
  `AndroidRootView`.

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
