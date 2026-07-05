# FurAffinity Project Notes

## Project Overview

Native iOS app for furaffinity.net. Logs in via web view, stores FA session cookies, fetches pages over HTTP, parses HTML, and renders native SwiftUI views.

- **Platform**: iOS 17.4+ · **Language**: Swift 6 · **Frameworks**: SwiftUI, Swift Concurrency · **Package Manager**: SPM

Two main code areas:
- `FurAffinity/`: iOS app — SwiftUI screens, app state, navigation, settings, image loading.
- `FAKit/`: Swift Package — `FAPages` (HTML parsers) and `FAKit` (domain models + session API).

## Architecture

`FurAffinityApp` injects `Model` → `RootView` shows `HomeView` (login/autologin via `FALoginView`) or `LoggedInView` (tabs). SwiftUI views call `Model` methods → `FASession` protocol → `OnlineFASession` (HTTP via `HTTPDataSource`, parsing via `FAPages`) → domain structs.

`FASession` is the extension point for new FA capabilities: add to the protocol, implement in `OnlineFASession`, add parser coverage in `FAPages`.

## Key Files

**App:**
- `FurAffinityApp.swift`: entry point, Amplitude init, `@UIApplicationDelegateAdaptor`.
- `AppDelegate.swift`: `OrientationGate`/`DeviceOrientationControl` — app is portrait everywhere except the landscape-capable story reader (iPhone only; iPad rotates freely).
- `Model.swift`: `@Observable @MainActor` — session, feeds, search results/query, notes, notifications, autorefresh, error storage.
- `Helpers/FATarget.swift`: FA URL → navigation target.
- `Helpers/InAppNavigation.swift`: `FATarget` → destination view.
- `Helper Views/RemoteView.swift`: loading/refresh wrapper for remote content.
- `Helpers/Kingfisher+FA.swift`: image loading/prefetching with FA headers.

**FAKit:**
- `FAKit/OnlineFASession.swift`: network impl — fetch, parse, map to domain models.
- `FAKit/HTTPDataSource.swift`: async HTTP abstraction.
- `FAKit/URLSession+HTTPDataSource.swift`: URLSession impl, status handling, Cloudflare error, logging.
- `FAKit/FALoginView.swift`: login web view + cookie cache.
- `FAPages/FAURLs.swift`: canonical FA URLs + parsing helpers.
- `FAPages/FASearchPage.swift` + `FASearchQuery.swift`: search results parser and typed query (keywords, tag include/exclude, author `@lower` scope, rating/type/gender, date range, sort). `FAUsername.swift`: shared username validator.
- `FAKit/StoryDocument/`: extracts reflowing rich text from downloaded story documents — `StoryDocument` (entry point, dispatches by extension: txt/md/rtf/pdf/docx), `PDFReflow`, `DocxTextParser`. Runs carry only font size + traits (no color) so the reader stays correct in light/dark. Bundled Roboto fonts live in `FAKit/Resources/Fonts/`.

`FAPages` parsers: immutable parsed fields, SwiftSoup init, log failures, throw on missing required HTML.

## Navigation

URL-centered. `FATarget.init?(with:)` maps FA URLs to typed cases; `view(for:)` returns the destination view. Convert FA links in rich HTML via `AttributedString.convertingLinksForInAppNavigation()` to route in-app when possible.

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

Use `FAImage`/`FAAnimatedImage` (not raw Kingfisher views) — they apply project downloader, cache policy, and logging. Use `prefetchThumbnails`/`prefetchAvatars` for list views.

## Cloudflare Challenge

`FAChallengeView` + `CloudflareChallengeCoordinator` intercept Cloudflare challenges transparently: present a WKWebView to solve, then retry. Callers of `URLSession.httpData()` need no special handling.

## Background Refresh

`BackgroundRefreshManager` drives background refresh; `BackgroundRefreshLifecycleModifier` wires it into the SwiftUI scene lifecycle.

## Tests

Scheme `FurAffinity` covers `FAKitTests`, `FAPagesTests`, `FurAffinityTests`. Parser tests use HTML fixtures under `FAKit/Tests/*/data/`; update fixtures when changing parser behavior.

HTML fixtures must **never** be generated or fabricated. Always capture real page source from furaffinity.net in a browser (logged-in, specific account as needed), then save the raw HTML as the fixture file.

```
xcodebuild test -scheme FurAffinity -destination 'platform=iOS Simulator,name=iPhone 17'
xcrun simctl list devices available | grep -E "iPhone|iPad"   # list available destinations
```

## Dependencies

App: AmplitudeSwift, Defaults, Kingfisher, SwiftUI-Introspect, Version, swift-algorithms. (Wrapping layouts use the in-house `Helper Views/FlowLayout.swift` — WrappingHStack was dropped.)
FAKit: SwiftSoup, Cache, SwiftGraph, swift-collections, ZIPFoundation (DOCX unzip for `StoryDocument`).

## Working Notes

- Layer discipline: parsers in `FAPages`, network/session in `FAKit`, UI state in `FurAffinity`.
- Only remote-loading wrappers that own `@Environment(Model.self)` (e.g. `RemoteSubmissionView`) may depend on `Model`. Leaf/content views must receive what they need via inputs or injected closures — never reach into `Model`.
- Prefer existing helpers before adding new wrappers.
- Tests: use fixture HTML, no live FA requests.
- Login: cookie-based; never handle the user's FA password directly.

## Planning Workflow

Use Plan Mode (Shift+Tab) before implementing. Work incrementally with tests.
- Apply changes in steps. Each step must be complete, tested, and committed before starting the next.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.

@LSP_SETUP.md
