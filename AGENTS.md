# FurAffinity Project Notes

## Project Overview

Native iOS app for furaffinity.net. Logs in via web view, stores FA session cookies, fetches pages over HTTP, parses HTML, and renders native SwiftUI views.

- **Platform**: iOS 18.0+ · **Language**: Swift 6 · **Frameworks**: SwiftUI, Swift Concurrency · **Package Manager**: SPM

Two main code areas:
- `FurAffinity/`: iOS app — SwiftUI screens, app state, navigation, settings, image loading.
- `FAKit/`: Swift Package — `FAPages` (HTML parsers) and `FAKit` (domain models + session API).

An in-progress **Android port** builds the same SwiftUI source with [Skip](https://skip.dev)
Fuse: the root `Package.swift` declares the `FurAffinityUI` target with `path: "FurAffinity"`,
next to the `Android/` (Gradle) and `Darwin/` scaffolding. Both platforms build the *same*
`FurAffinity/` directory, split by the `iOS/`/`Android/` convention below; skipstone walks
the whole tree, so every source it must not build carries `#if !FA_SKIP_MODULE`. Ported so
far: login (shared `HomeView` + autologin), the Followed feed, the submission screen
(images, stories, music, comments, Save/Share, "Send a Note"), Notifications (with the
journal screen and swipe-to-delete behind an Undo snackbar) and Settings. Not ported:
Notes, Profile, Explore. `Android/README.md` indexes the topic docs under
`Android/docs/`; read the relevant one before touching Android code. What every session
needs to know:

- **FAKit carries the skipstone plugin too**, so it owns the Android web layer
  (`FAKit/Sources/FAKit/Android/`); its basenames share the uniqueness rule below. The
  iOS app pays 37 MB Release instead of 27 for it.
- **Logging**: `#if canImport(os) import os #else import OSCompat`. `OSCompat` (in the
  sibling `FALogging/` package) must **not** be named `os`, and FAKit gates SwiftUI on
  `#if !os(Android)`, never `canImport` — `build-and-run.md` § Module-name poisoning.
- **`FALogging` is its own package** so FAKit and FAPages link it dynamically: a target
  dependency inside one package is copied into each product, which once gave three
  `PersistentLogStore.shared`s in one log file. `Scripts/Android/check-shared-globals.sh`
  guards it; Xcode reaches the package only through an `XCLocalSwiftPackageReference`,
  never also a folder reference — `shared-sources.md` § One module, one image.
- **Five dependencies are forked** on `Ceylo/<repo>` `android` branches: `Defaults`,
  `skip-ui`, `skip-fuse-ui`, `skip-web` (dependency identity only) and `Kingfisher`, which
  builds for Android, so `FAImage` is a real `KFImage` on both platforms — `forks.md`.
- **Pages and images share one `OkHttpClient`** on Android (`FAHttpClient.kt`), because
  Cloudflare judges a connection and a challenge is repaired by evicting it — `images.md`,
  `cloudflare-and-login.md`. HTTP/2 is measured and off.
- **Sentry** (crashes and ANRs, both platforms, consent toggle on by default, never the
  log) and **Amplitude** run on both — `crash-reporting.md`, `analytics.md`.
  `Scripts/check-crash-reporting.sh ios|android` is the proof a symbolicated crash still
  arrives. Our packages build release with `-disable-cmo` so crash frames keep their lines.
- Profile Android with `Scripts/Android/run.sh --profile`, then
  `Scripts/Android/profile.sh cpu|trace|mem` — `profiling.md`.

## Architecture

`FurAffinityApp` injects `Model` → `RootView` shows `HomeView` (login/autologin via `FALoginView`) or `LoggedInView` (tabs). SwiftUI views call `Model` methods → `FASession` protocol → `OnlineFASession` (HTTP via `HTTPDataSource`, parsing via `FAPages`) → domain structs.

`FASession` is the extension point for new FA capabilities: add to the protocol, implement in `OnlineFASession`, add parser coverage in `FAPages`.

## Key Files

**App:**
- `iOS/FurAffinityApp.swift`: entry point, Amplitude init, `@UIApplicationDelegateAdaptor`.
- `iOS/AppDelegate.swift`: `OrientationGate`/`DeviceOrientationControl` — app is portrait everywhere except the landscape-capable story reader (iPhone only; iPad rotates freely).
- `Model.swift`: `@Observable @MainActor` — session, feeds, search results/query, notes, notifications, autorefresh, error storage.
- `Helpers/FATarget.swift`: FA URL → navigation target.
- `Helpers/iOS/InAppNavigation.swift` · `Helpers/Android/InAppNavigation+Android.swift`: `FATarget` → destination view.
- `Helpers/InAppLinkConversion.swift`: `appNavigationScheme`. Kept apart from `InAppNavigation.swift` (no SwiftUI) so both platforms share it — which is why it stays in the base while its sibling has an `iOS/` and an `Android/` build.
- `Helper Views/RemoteView.swift`: loading/refresh wrapper for remote content.
- `Helpers/Kingfisher+FA.swift`: image loading/prefetching with FA headers; shared, with the transport forked per platform.

**FAKit:**
- `FAKit/OnlineFASession.swift`: network impl — fetch, parse, map to domain models.
- `FAKit/HTTPDataSource.swift`: async HTTP abstraction.
- `FAKit/iOS/URLSession+HTTPDataSource.swift`: URLSession impl, status handling, Cloudflare error, logging.
- `FAKit/iOS/FALoginView.swift`: login web view + cookie cache.
- `FAPages/FAURLs.swift`: canonical FA URLs + parsing helpers.
- `FAPages/FASearchPage.swift` + `FASearchQuery.swift`: search results parser and typed query (keywords, tag include/exclude, author `@lower` scope, rating/type/gender, date range, sort). `FAUsername.swift`: shared username validator.
- `FAKit/StoryDocument/iOS/`: extracts reflowing rich text from downloaded story documents — `StoryDocument` (entry point, dispatches by extension: txt/md/rtf/pdf/docx), `PDFReflow`, `DocxTextParser`. Runs carry only font size + traits (no color) so the reader stays correct in light/dark. Bundled Roboto fonts live in `FAKit/Resources/Fonts/`.

`FAPages` parsers: immutable parsed fields, SwiftSoup init, log failures, throw on missing required HTML.

## Navigation

URL-centered. `FATarget.init?(with:)` maps FA URLs to typed cases; `view(for:)` returns the destination view.

Every in-app link routes **in-process** through `NavigationStream` (`Helper Views/FALink.swift`), never out through `UIApplication.open` — a LaunchServices round trip fails when the app is hidden behind Face ID, and can surface a different install sharing the URL scheme. Use `FALink` for tappable views; taps on links inside rich HTML are intercepted before they can become an `openURL` — by `HTMLView`'s `UITextViewDelegate` on iOS and by its `onLinkTap` on Android — and anything `FATarget(with:)` matches goes to the stream, the rest to the browser. The `furaffinity-app-navigation` scheme stays registered on iOS purely as an *external* entry point (Reminders, Shortcuts) handled by `.onOpenURL`; Android registers no scheme.

## Submission Content Kinds

`FASubmission.content` is an enum — `.image(ImageContent)`, `.text(TextContent)`, `.audio(AudioContent)` (typealiased from `FASubmissionPage`). `SubmissionView` switches on it to render `SubmissionMainImage`, `SubmissionTextContent`, or `SubmissionAudioContent`; text and audio are document-backed (Save to Files / Share the downloaded file), image is not.

- **Text (story)**: `Submissions/Text Submissions/` — `StoryReaderView` renders `StoryDocument`-extracted rich text with a Reflowed/Original toggle (Original falls back to `QuickLookPreview` of the raw document) and landscape support (via `DeviceOrientationControl`). See [[project_pdfkit_lossy_extraction]].
- **Audio (music)**: `Submissions/Audio Submissions/` — `AudioPlaybackController` streams via `AVPlayer` and publishes lock-screen playback via `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` (`MPMediaItemArtwork` must be built off-main, see [[project_mpartwork_isolation_crash]]); `AudioPlayerControls`/`AudioScrubber` are the inline UI.

## Search / Explore

The first tab is `SubmissionsTabView`, which hosts two modes — **Followed** (`SubmissionsFeedView`, the watched-users feed) and **Explore** (`ExplorationView`, furaffinity.net search). The mode switch and context action float as Liquid-Glass buttons over the list corner instead of a nav bar. Floating controls use `floatingGlass` rather than `glassEffect`: the same glass, plus a light shadow in dark mode on Android. `Model.searchSubmissions`/`loadMoreSearchResults` call `FASession.search(FASearchQuery)`; the query is persisted (`Defaults[.lastSearchQuery]`) so filters are remembered. Search inputs (tags via `TagSearchEditor`, author via `UsernameField`, rating/type/etc.) live in the `SearchFiltersView` sheet — `.searchable` can't be used here, see [[project_searchable_sibling_suppression]].

## Comment Threads

`Comments/` renders threaded replies with connector lines (`CommentThreadConnector`, widths measured via `CommentsWidthMeasuring`). Very deep sub-threads collapse behind a `ContinueThreadRow` that pushes a focused view; `CommentThreadFocus` carries the deep-linked cid to auto-focus.

## Remote Loading

Prefer `RemoteView` (no preview state, default toolbar item) or `PreviewableRemoteView` (preview model available, or view owns toolbar). Use `storeLocalizedError(in:action:webBrowserURL:)` for error surfacing. Roll back optimistic mutations via `UpdateHandler` on failure.

## State and Errors

`Model` is `@MainActor` — keep UI mutations on the main actor; network/parsing behind async FAKit calls. User-facing errors go through `ErrorStorage`/`RichLocalizedError`; `storeError` preserves the first error and logs skipped ones.

## Images

Use `FAImage`/`FAAnimatedImage` (not raw Kingfisher views) — they apply project downloader, cache policy, and logging. Use `prefetchThumbnails`/`prefetchAvatars` for list views. Both return `KFImage` on Android too; what differs there is the downloader (`FAOkHttpDownloader`, so images ride the page path's OkHttp connection pool) and the absence of an animated path, so `FAAnimatedImage` is the same static view. See `Android/docs/images.md`.

## Cloudflare Challenge

`FAChallengeView` + `CloudflareChallengeCoordinator` intercept Cloudflare challenges transparently: present a WKWebView to solve, then retry. Callers of `URLSession.httpData()` need no special handling.

## Background Refresh

`BackgroundRefreshManager` drives background refresh; `BackgroundRefreshLifecycleModifier` wires it into the SwiftUI scene lifecycle.

## Tests

Scheme `FurAffinity` covers `FAKitTests`, `FAPagesTests`, `FurAffinityTests`. Parser tests use HTML fixtures under `FAKit/Tests/*/data/`; update fixtures when changing parser behavior.

HTML fixtures must **never** be generated or fabricated. Always capture real page source from furaffinity.net in a browser (logged-in, specific account as needed), then save the raw HTML as the fixture file.

```
xcodebuild test -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

`Scripts/iOS/simulator.sh` manages this worktree's *own* device — `FA <worktree
directory>`, an `iPhone 17 / iOS 26.5` created on first use (`--help` for another
device type, `--shutdown` to stop one). Each worktree gets its own so branches
don't overwrite each other's app container; shut down the ones you aren't using.

Destination-by-id also retires the `OS=26.5` pinning trap: a bare
`name=iPhone 17` resolves to `OS:latest`, the locally-installed iOS 27.0 beta
runtime, which has only an "iPhone 17 **Pro**" and so matches nothing.

On Android, with the emulator running (`Scripts/Android/start-emulator.sh`):

```
Scripts/Android/test.sh
```

It runs FAKit's package and the root package's `FurAffinityUITests` — the
`FurAffinityTests` files that build for Android, picking their `@testable import` on
`FA_SKIP_MODULE` — and fails below a case-count floor. Outside CI it builds in a
leased build slot, through Gradle's `faAndroidTest` (see Working Notes). CI's `Build Android App` job runs
the same script. Which files stay iOS-only, and why: `Android/docs/build-and-run.md`
§ Test.

## Dependencies

App: AmplitudeSwift, Defaults, Kingfisher, SwiftUI-Introspect, Version, swift-algorithms. (Wrapping layouts use the in-house `Helper Views/iOS/FlowLayout.swift` — WrappingHStack was dropped.)
FAKit: FALogging (the sibling package, which also vends `OSCompat`), SwiftSoup, Cache, SwiftGraph, swift-collections, ZIPFoundation (DOCX unzip for `StoryDocument`).

## Working Notes

- Layer discipline: parsers in `FAPages`, network/session in `FAKit`, UI state in `FurAffinity`.
- Platform split, applied recursively in every directory: a file that only one platform
  compiles goes in an `iOS/` or `Android/` subdirectory **of its own parent**, so the two
  builds of one screen sit side by side (`Helper Views/iOS/Zoomable.swift` next to
  `Helper Views/Android/Zoomable+Android.swift`). Everything else stays in the common base —
  including plain-SwiftUI files that simply are not ported yet. Those subdirectories hold
  source files, not further trees. `Scripts/`, `Distribution/` and FAKit follow the same
  rule. `Assets.xcassets` stays in the base — it is the single source of truth the Android
  asset script reads, and `Package.swift` excludes it from the Skip target.
- **`#if !FA_SKIP_MODULE` is what keeps a file out of the Android build.** skipstone walks
  the whole target directory and honors neither SwiftPM `sources:` nor `exclude:`, so
  anything it sees must either build for Android or be guarded. Porting a screen means
  deleting its guard. It must be `FA_SKIP_MODULE`, never `os(Android)`: the module is
  compiled twice for Skip — the Android cross-compile and a host build where `os(Android)`
  is **false** — so an `os(Android)` guard leaves UIKit/Kingfisher/Photos imports to
  resolve in a target that does not depend on them.
- **Basenames must be unique across the whole `FurAffinity/` tree — and across
  `FAKit/Sources/FAKit/`, which skipstone now processes too.** SwiftPM derives one
  object file per basename and skipstone one `<Name>_Bridge.swift`, both flattened, so a
  matching `iOS/`+`Android/` pair collides with "multiple producers" — even when the iOS
  half is guarded down to nothing. Hence the `+Android` suffix on the substitution
  files; the directory still carries the meaning.
- Only remote-loading wrappers that own `@Environment(Model.self)` (e.g. `RemoteSubmissionView`) may depend on `Model`. Leaf/content views must receive what they need via inputs or injected closures — never reach into `Model`.
- **Several worktrees at once.** iOS gets a simulator device per worktree
  (`Scripts/iOS/simulator.sh`, above); Android keeps sharing the one emulator, and
  instead gives each worktree its own **debug** app — `applicationIdSuffix` and
  launcher label derived from the worktree directory name in
  `Android/app/build.gradle.kts`. Run it with `Scripts/Android/run.sh`
  rather than `skip app launch --android`, which starts the unsuffixed id; wrap
  anything else that drives the emulator from a second worktree in
  `Scripts/Android/with-emulator-lock.sh`. Release is untouched on both platforms.
  The cost of all this: each worktree's app has its **own container**, so a separate
  FA login, cookie jar and (on Android) Cloudflare clearance.
  A new worktree's Android build reuses the others' work: Gradle's build cache holds
  the Kotlin compiles, and a Gradle build compiles the Swift side in a leased
  **build slot** (`DerivedData/android-slot-<n>`, a synced source copy shared by all
  worktrees), ~18 s instead of 2–4 min (`Android/docs/build-and-run.md` § Build
  cache, § Build slots). Compiler errors therefore point into the slot: edit the
  worktree's file, never the slot's, which the next sync overwrites. `rm -rf .build`
  or `Scripts/Android/clean.sh` still gives a clean build. On iOS, Xcode's
  compilation cache is shared too once the FA Compilation Cache toolchain is
  selected (`COMPILATION_CACHE.md`).
  Run `Scripts/install-git-hooks.sh` once per clone: a new worktree's `post-checkout`
  then seeds its DerivedData/SourcePackages from a sibling's pinned to the same
  `Package.resolved` (`Scripts/iOS/seed-source-packages.py`), skipping SwiftPM's
  package resolution and ~29 checkouts.
  Removing a worktree leaves behind what is keyed by its path or name elsewhere:
  its emulator app, simulator, DerivedData dirs (the Skip project's have no
  `info.plist`, only a path hash) and XcodeBuildMCP workspace.
  `Scripts/cleanup-worktree.py <name>` removes a merged worktree with all of them
  and its branch; `--orphans` sweeps what worktrees removed without it left, and
  reports what it kept, why, and each branch's storage.
- **A bridged view's `@State`/`@Environment` must not be `private`.** skipstone
  generates the bridge from the property list it can see, so a private one is
  silently left out and the view never recomposes. Call sites carry a one-line
  reminder because the natural instinct is to add `private` back.
- Prefer existing helpers before adding new wrappers.
- Tests: use fixture HTML, no live FA requests.
- Login: cookie-based; never handle the user's FA password directly.

## Planning Workflow

Use Plan Mode (Shift+Tab) before implementing. Work incrementally with tests.
- Apply changes in steps. Each step must be complete, tested, and committed before starting the next.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.

@LSP_SETUP.md
