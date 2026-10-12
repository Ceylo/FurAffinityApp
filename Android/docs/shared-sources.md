# Shared sources

## Why everything unported is guarded

Skip's transpiler (`skipstone`) walks the **entire** target-directory tree; it honors
neither SwiftPM `sources:` nor `exclude:`. The target's `path:` is `FurAffinity`, so
every `.swift` in the app is offered to skipstone, and anything the Android build must
not compile is wrapped, whole-file, in:

```
#if !FA_SKIP_MODULE
…
#endif
```

That covers the iOS-only files *and* the plain-SwiftUI screens that are not ported yet.
**Porting a screen is deleting its guard.**

`FA_SKIP_MODULE` is defined by `Package.swift` for this target. It has to be that flag
rather than `os(Android)`, because the module is compiled **twice** for Skip: the
Android cross-compile, and the Darwin bridge (`arm64-apple-ios`), where `os(Android)` is
*false*. An `os(Android)`-guarded file is therefore included in the Darwin compile, and
its iOS-only imports have nothing to resolve against:

```
FurAffinity/Helpers/iOS/ImageBlur.swift:11:8: error: no such module 'Kingfisher'
```

A Gradle build (`run.sh`, `./gradlew :app:assembleDebug`) catches that, since its
prebuild compiles the Darwin bridge. **`skip android build` does not**: it only
cross-compiles for Android.

## Basenames must be unique across the tree

SwiftPM derives one object file per source *basename*, and skipstone one
`<Name>_Bridge.swift`, both flattened into a single directory, so two files with the
same name anywhere in the target fail the build with "multiple producers". This bites
`iOS/`+`Android/` pairs even when one half is guarded, since the guarded file still
emits an empty bridge. Hence the `…+Android.swift` names; the directory carries the
platform meaning, the suffix only keeps the name unique. **The rule spans FAKit too**,
which also carries the plugin: `FALoginView+Android.swift`, `FAChallengeView+Android.swift`.

## Defaults

`UserDefaults.standard` means two different things on Android. In a module skipstone
processes, it emits `typealias UserDefaults = AndroidUserDefaults`, so `.standard` is
the app's `SharedPreferences` (`shared_prefs/defaults.xml`), where `@AppStorage` writes
land. `Defaults` is a plain SwiftPM dependency, so *its* `.standard` is Foundation's
own: a separate store nothing reads, which never reaches disk. That is why
`Defaults[key] = value` used to vanish while reads returned the new value.

The fork exposes `Defaults.defaultSuite`, and `Helpers/Android/AndroidDefaultsSuite.swift`
assigns the shared-preferences-backed one from `onInit()`, before the first key is
created: a key captures its suite and registers its default into it right away. So
`Defaults.runSettingsMigrations()` runs *after* `installDefaultsSuite()`. `Bool`, `Int`
and `String` cross JNI to shared_prefs unchanged.

`@Default(.someKey)` works on Android too, spelled as on iOS. `Ceylo/Defaults@android`
guards the package's SwiftUI support out (importing SwiftUI from a plain package breaks
the build), so `Helpers/Android/AndroidDefault.swift` re-declares the wrapper over a
box of its own (see [Rules for shared sources](#rules-for-shared-sources)).

To check what actually persisted — never trust a read-back of `Defaults[…]`, that is
what hid this:

```
adb shell run-as com.example.id1234.<worktree> cat shared_prefs/defaults.xml
```

## One module, one image

A module that holds process-global state must be defined by **exactly one** `.so` in
the APK, or each consumer gets its own copy of every global. SwiftPM decides that per
*edge*: a **cross-package product** is linked dynamically, one image; a **target
dependency inside the same package** is linked *statically into each product of that
package*, even a `.dynamic` one.

That is what happened to `FALogging` while it was a target inside `FAKit`:
`libFAKit.so` and `libFAPages.so` each absorbed a private copy. Three copies of
`PersistentLogStore.shared` wrote `files/Logs/app.log` at three independent offsets,
truncating and overwriting lines in the file users export from Settings. So
`FALogging` (with `OSCompat`) is its own package at the repo root, and the **`.dynamic`
rewrite under `SKIP_BRIDGE`** in its manifest is load-bearing: with an automatic
product no `libFALogging.so` is produced at all.

None of this is visible from Swift: an `assert` comparing the global from two modules
passes, because both sides bind to the caller's copy. Only the symbol tables tell, so
the check is a build-time one:

```
Scripts/Android/check-shared-globals.sh [debug|release]
```

It counts, per image, the defined `OBJECT` symbols of each listed module and fails
naming every extra definer. `run.sh` and CI run it. Add a module to its list when one
grows mutable process-global state and more than one image consumes it.

Since skip-bridge 0.18 the Gradle build uses SwiftPM's `swiftbuild`, which makes
"linked as a static library by … and …" an error, so the rule now holds for stateless
modules too. Hence `FAKit`'s single product carrying both `FAKit` and `FAPages`, and a
root target with no `FAPages` edge of its own.

### What the split costs the Xcode project

- **A package that is already another package's path dependency does not become a
  workspace root on its own.** `FAKit` reaches `FALogging` as `.package(path:
  "../FALogging")`, so Xcode builds its targets but exposes none of its *products*
  (`Missing package product 'FALogging'`), while `xcodebuild` is happy. The fix is an
  explicit `XCLocalSwiftPackageReference` (`relativePath = FALogging`), which needs
  `objectVersion = 60`. **FALogging must have no folder `PBXFileReference`**: with
  both, Xcode fails again.
- **Dropping that folder reference costs the scheme its container**, so a testable
  there was silently skipped. `FALoggingTests` is therefore declared in
  `FAKit/Package.swift` over `FAKit/Tests/FALoggingTests/`, and the scheme keeps
  `container:FAKit`.

Check the test count, not just the exit status: a dropped testable does not fail the
build. On Android, `Scripts/Android/test.sh` checks a floor per package.

## Rules for shared sources

**Two modules carry the skipstone plugin**: FurAffinityUI, and FAKit, so it could own
the Android web layer (only a plugin-carrying module gets the Kotlin glue a bridged
view's `@State` needs). Everything below applies to `FAKit/Sources/FAKit/` too, except
that FAKit's `FA_SKIP_MODULE` is gated on `SKIP_BRIDGE`, which the Darwin bridge pass
does not set, so there FAKit compiles exactly as in Xcode.

An *unguarded* file under `FurAffinity/` is compiled **twice more** than the iOS target
compiles it: for Android (`os(Android)` true) and for the Darwin bridge (`os(Android)`
**false**, UIKit importable). Neither sees the iOS app target, so:

- Guard anything that exists only in the Xcode target with `#if !FA_SKIP_MODULE`;
  `os(Android)` cannot express it.
- Leave `#Preview`s unguarded. On Android they come from the skip-fuse-ui fork and
  expand to nothing, but the body is still type-checked, so a stale preview fails the
  Android build too. A preview-only helper such as `withAsync` is `// SKIP @nobridge`.
- Guard Darwin-only frameworks and APIs (Liquid Glass, `UIKit` types) with `#if
  !os(Android)` / `#if canImport(…)`, but reach for it last: `Model.swift` was fenced
  twice and now has no conditional at all, since `Defaults.updates` got an Android
  implementation and the `willEnterForegroundNotification` loop became the shared
  `scenePhase` modifier `ForegroundAutorefresh`.
- **An Android substitution file must not be `#if os(Android)`-guarded.** When a shared
  file calls a name that resolves per platform (`ImageCacheControl`,
  `clearLoginCookies`, `share`), the Android declaration lives in an `Android/`
  directory while its `iOS/` twin is guarded out. `os(Android)` is false for the Darwin
  bridge compile, so a file-level guard leaves shared callers with *no* declaration.
  Leave the file unguarded and put `#if canImport(Android)` around the JNI inside, with
  a Darwin no-op, as `ImageFetchBridge` does. `skip android build` stays green on this
  mistake; a Gradle build fails.

  Three exceptions. A name a *package* already declares on Darwin:
  `AndroidDefault.swift` is `#if os(Android)`-guarded because the bridge compile
  resolves `Default` from the real Defaults package. **The rule follows the callers
  into FAKit**: `Android/FAHTTPDataSource.swift`, `FAWebSession.swift` and
  `FAWebView.swift` are unguarded because unguarded app files name them, so the iOS
  app compiles them too; only `iOS/` files whose *frameworks* are Darwin-only (UIKit,
  WebKit, PDFKit, Cache) can be guarded on the platform. And a Darwin twin in *this
  same module*: `FALoginView+Android.swift` and `FAChallengeView+Android.swift` take
  `#if os(Android)` against their twins' `#if !os(Android)`. That is safe for a bridged
  view because **skipstone evaluates `os(Android)` as true**, so this half still gets
  its full bridge and the twin's comes out empty. [Check the
  bridge](#checking-a-generated-bridge) after any change: an empty one renders once
  and never recomposes.
- **`import os` needs `#if canImport(os)`.** Android's Swift SDK has no `os` module, so
  the `FALogging` package ships `OSCompat`, which vends `AndroidLogging`'s `Logger` and
  an ATrace-backed `OSSignposter`. It is a dependency only on Android, so Darwin still
  resolves the system module:

  ```swift
  #if canImport(os)
  import os
  #else
  import OSCompat
  #endif
  ```

  It must **not** be named `os` (see [Module-name
  poisoning](build-and-run.md#module-name-poisoning)). Anything else from `os` (e.g.
  `OSAllocatedUnfairLock`) needs a guard, or an addition to the shim.
- <a name="every-observable-needs-skipandroidbridge-in-scope"></a>**Every `@Observable`
  compiled for Android must have `SkipAndroidBridge` in scope in its own file**: in
  practice `import SwiftUI`, never `import Observation` on its own. The macro expands to
  `Observation.ObservationRegistrar`. `SkipAndroidBridge` vends a `struct Observation`
  whose registrar reaches Compose, and it shadows the stdlib *module* only where it is
  imported (`SkipSwiftUI` re-exports it, hence `import SwiftUI`). Without it the view
  compiles, mutates, and never re-renders, with no warning; `AppInformation` and
  `MediaSaveHandler+Android` were both inert this way until one import swap. To check
  which registrar a file got:

  ```
  nm -u "$(find "$(cat .build/.fa-slot)/.build" -path '*Debug-android-aarch64*' -name '<File>.o' | head -1)" \
    | xcrun swift-demangle | grep ObservationRegistrar
  ```

  `SkipAndroidBridge.Observation.ObservationRegistrar` is bridged; a bare
  `Observation.ObservationRegistrar` alone is inert. In FAKit, which gates SwiftUI on
  the platform, the import is `#if os(Android) import SwiftUI #else import Observation
  #endif` (`CloudflareChallengeCoordinator`), and skipstone does warn there. Adding
  `skip-android-bridge` alone instead fails on `missing required module 'CJNI'`: the
  plugin brings the whole closure.
- `#if` blocks must contain balanced braces: split an `if/else` into two whole branches
  rather than fencing one arm.
- `@State`/`@Environment` on a bridged view must be **internal**, not `private`, and so
  must a `ViewModifier` struct itself. skipstone's bridge calls a *generic*
  `ViewModifier`'s `body` without the `content:` label, so type-erase the generic
  parameter instead (see `ScrollToItemModifier`).
- **State property wrappers are matched by attribute name.** skipstone emits a bridged
  view's `Java_initState_<name>` from the literal attribute (`@State`, `@AppStorage`, …),
  so a wrapper of your own gets no Compose state and neither persists nor recomposes,
  silently; wrapping or typealiasing `AppStorage` does not help. A custom wrapper works
  if it **owns its own box**: `AndroidDefault.swift` keeps a static
  `BridgedAppStorageBox` per key (public skip-fuse-ui API), which suits process-lived
  settings but does **not** generalize to per-view state.
- **`@State` inside `#if DEBUG` never recomposes**: skipstone skips those blocks when it
  generates the bridge. Declare it outside the guard.
- `@Entry` works, from the skip-fuse-ui fork, but only in an `EnvironmentValues`
  extension.
- **`CGSize` is two types here**: `Foundation.CGSize` (which FAKit extends and takes)
  and SkipSwiftUI's façade one (`GeometryProxy.size`). As a **type annotation** the
  bare name is ambiguous; qualify it. A façade value lacks FAKit's helpers: convert it
  with `.faSize` (`CGSizeBridge.swift`), which lives in its own file because `import
  SkipSwiftUI` makes `GeometryProxy` ambiguous.
- **Don't call `withAnimation` from shared code**, and key `.animation(_:value:)` on a
  `Bool`, `Int` or `String`. See [screens.md § `withAnimation` marks the
  whole frame](screens.md#withanimation-marks-the-whole-frame-process-wide), which also has
  the `.transition` contract.
- **An armed animation eases every per-frame write in the same subtree.** `.offset` and
  `.scaleEffect` go through an `Animatable` that re-launches `animateTo` on each write
  while an animation is armed, so a gesture writing 60 times a second lags its finger.
  The resume record is `rememberSaveable`, so an interrupted animation's start value
  even outlives a sheet dismissal. Arm `.animation(_:value:)` on a value **set once**,
  such as a counter bumped by the action.
- **To animate a value a gesture also writes, step it yourself**, as `Zoomable+Android`'s
  `runMotion` does. Nothing in SkipSwiftUI aligns work to a frame, so it ticks every
  4 ms and lets Compose coalesce: a stepped fling held one distinct frame per vsync on a
  60 Hz AVD, as Compose's own animation did. A `Task` outlives its composition, so
  cancel it from `onDisappear`.
- **SkipUI's `.offset` is Compose's *layout* offset**: the moved node is still clipped
  to its original rect. Size content to the viewport first, or keep the offset bounded.
- **A bridged `@State` survives a sheet dismissal**, being `rememberSaveable`. Presented
  content resets itself from `onAppear`, as `Zoomable+Android` does.

### Checking a generated bridge

The bridges are where most of the silent failures above show: an empty
`<Name>_Bridge.swift`, or a property with no `Java_initState_`. Under a Gradle build
they live in the slot (see [build slots](build-and-run.md#build-slots)):

```
grep -l Java_initState_ \
  "$(cat .build/.fa-slot)"/.build/plugins/outputs/*/FurAffinityUI/destination/skipstone/FurAffinityUI/build/swift/plugins/outputs/*/*/destination/skipstone/SkipBridgeGenerated/<View>_Bridge.swift
```

The second `*/*` covers FAKit's bridges (`fakit/FAKit`) as well as the app's.
