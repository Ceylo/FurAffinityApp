# FurAffinity Project Notes

## Project Overview

Native iOS app for furaffinity.net. Logs in via web view, stores FA session cookies, fetches pages over HTTP, parses HTML, and renders native SwiftUI views.

- **Platform**: iOS 18.0+ · **Language**: Swift 6 · **Frameworks**: SwiftUI, Swift Concurrency · **Package Manager**: SPM

Two main code areas:
- `FurAffinity/`: iOS app — SwiftUI screens, app state, navigation, settings, image loading.
- `FAKit/`: Swift Package — `FAPages` (HTML parsers) and `FAKit` (domain models + session API).

An in-progress **Android port** builds the same SwiftUI source with [Skip](https://skip.dev)
Fuse (root `Package.swift` + `FurAffinityUI/` target + `Android/`/`Darwin/` scaffolding).
Both platforms build the *same* directory — `FurAffinity/` — split by the `iOS/`/`Android/`
convention below. The Skip target's `path:` is `FurAffinity`, so skipstone walks the whole
tree and every source it must not build carries `#if !FA_SKIP_MODULE`. The iOS Xcode target
is unaffected. Ported so far: the login screen (shared
`HomeView` + autologin, over an Android `FALoginView`), the Followed feed (on the shared
`SubmissionsFeedView` container, badge and refresh choreography included), the
submission detail screen (shared `SubmissionMainImage`, a zoomable viewer presented from
a `fadingSheet` and dismissed by pulling it down, favorite, Save/Share, rich-text
description with in-app links, read-only comments, metadata) and the Settings tab (shared
`SettingsView` / `NotificationSettingsView`, image-cache control, log sharing, logout).
FA's rich text is rendered by Compose's own HTML parser: `FAKit/Sources/FAKit/RichText/`
normalises the markup into the subset `AnnotatedString.fromHtml` understands (and cuts it
at its `<hr>`s, which that parser drops), and `Helper Views/Android/HTMLView+Android.swift`
hands each fragment to `Text(html:)`.
FAKit carries the skipstone plugin too (`FAKit/Sources/FAKit/Skip/skip.yml`), which is
what lets it own the Android web layer in `FAKit/Sources/FAKit/Android/`: a *bridged*
view only gets its Kotlin `@State` glue from a plugin-carrying module. The two Kotlin
bridges that layer needs from the app come back as hooks installed in
`FurAffinityUIAppDelegate.onInit`. The iOS app pays 37 MB Release instead of 27, and 11
embedded frameworks instead of 1.
Logging works on both platforms via `#if canImport(os) import os #else import OSCompat`:
the sibling `FALogging/` package ships an Android-only `OSCompat` target
(`FALogging/Sources/OSCompat/`) vending `Logger` (→ logcat) and an ATrace-backed
`OSSignposter` (→ Perfetto).
It must **not** be named `os` — a module by that name makes `canImport(os)` true for
the whole Android build; see `Android/docs/build-and-run.md` § Module-name poisoning,
which is also why FAKit gates SwiftUI on `#if !os(Android)` rather than `canImport`.
`FALogging` is a package rather than a FAKit target so that FAKit and FAPages link it
**dynamically**: a target dependency inside one package is absorbed statically into
each of its products, which gave the app three copies of `PersistentLogStore.shared`
destroying each other's writes in one log file. See `Android/docs/shared-sources.md`
§ One module, one image; `Scripts/Android/check-shared-globals.sh`, run by
`Scripts/Android/run.sh`, is the guard. Xcode reaches that package only through an
`XCLocalSwiftPackageReference` and **must not** also have a folder reference for it,
which is why `FALoggingTests` is declared in `FAKit/Package.swift` — same doc,
§ What the split costs the Xcode project. Five dependencies are forked on
`Ceylo/<repo>` `android` branches — `Defaults`, `skip-ui`/`skip-fuse-ui`
(the latter two for `listRowInsets`, `Text(html:)`, `Text(AttributedString)` /
`Text(_:inlineViews:)`, `Text + Text` and `FlowRow`, all unavailable or absent
upstream; skip-fuse-ui alone also for `#Preview`), `skip-web` (dependency identity only: SwiftPM allows one location per
package identity, so every chain must name `Ceylo/skip-ui` — see
`Android/docs/forks.md` § One location per identity) and `Kingfisher`, which now
builds for Android: its decoding is substituted onto SkipSwiftUI's `UIImage`
rather than ImageIO, and its SwiftUI
layer onto `@Observable`, so `FAImage(_:)` is a real `KFImage` on both platforms.
Only the *transport* under it is Android-only — `FAOkHttpDownloader` over
`FAImageStore` + `FAImageFetchBridge` — and Save/Share goes through `FAMediaBridge`.
Pages and images share **one** `OkHttpClient` and one connection
pool (`FAHttpClient.kt`, reached from FAKit through `FAWebSession.nativeTransport`),
because Cloudflare judges a connection: a challenge on it is repaired — evict, solve
in the WebView, redial — rather than retried into. HTTP/2 is measured and off; see
`Android/docs/images.md`. `Android/README.md` orients and indexes the topic docs under
`Android/docs/`. Profile Android with `Scripts/Android/run.sh --profile` then
`Scripts/Android/profile.sh cpu|trace|mem` — see `Android/docs/profiling.md`.

Crashes and ANRs report to **Sentry** on both platforms, one project split by
`os.name`: shared config in `FurAffinity/Helpers/CrashReporting.swift`,
sentry-cocoa on iOS and sentry-android (tombstones on Android 12+, the NDK signal
handler below) behind `FACrashReportingBridge`. Three distribution channels each
need a DSN and their symbols on the server: the DSN comes from the distribution
stash for both local channels and from a CI secret for the IPA workflow, while
dSYMs go up from an archive-only `Upload dSYMs` aggregate target (`ACTION=install`)
and the `.so` files and R8 mapping from the Sentry Gradle plugin. Our packages
build release with `-disable-cmo`, because Swift's
cross-module optimization copies functions between modules *without a line table*
and a crash inside one loses its file and line. Every event carries a `commit` tag,
HEAD's short hash, stamped by the unsandboxed `Commit Stamp` target into
`Info.plist` on iOS and by `BuildConfig.GIT_COMMIT` on Android; the app target itself
keeps the script sandbox. Consent is a Settings toggle, on by
default; the application log is never sent. `Scripts/check-crash-reporting.sh
ios|android` crashes the app on purpose and asserts the resulting Sentry event has
the right `File.swift:line`. See `Android/docs/crash-reporting.md`.

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

The first tab is `SubmissionsTabView`, which hosts two modes — **Followed** (`SubmissionsFeedView`, the watched-users feed) and **Explore** (`ExplorationView`, furaffinity.net search). The mode switch and context action float as Liquid-Glass buttons over the list corner instead of a nav bar. `Model.searchSubmissions`/`loadMoreSearchResults` call `FASession.search(FASearchQuery)`; the query is persisted (`Defaults[.lastSearchQuery]`) so filters are remembered. Search inputs (tags via `TagSearchEditor`, author via `UsernameField`, rating/type/etc.) live in the `SearchFiltersView` sheet — `.searchable` can't be used here, see [[project_searchable_sibling_suppression]].

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
  DerivedData keeps one directory per worktree path *ever* used, so it grows with
  worktrees that no longer exist. To list the orphans (then delete what it prints):
  ```
  for d in ~/Library/Developer/Xcode/DerivedData/*/; do
    p=$(plutil -extract WorkspacePath raw -o - "$d/info.plist" 2>/dev/null)
    [ -n "$p" ] && [ ! -e "$p" ] && echo "$d"
  done
  ```
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
