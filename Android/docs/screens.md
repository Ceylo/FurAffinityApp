# Screens

## Followed feed

The feed container is **shared**: `SubmissionsFeedView.swift` builds for both
platforms, so Android gets the refresh badge, swipe-to-delete, the cold-launch restore
check and foreground autorefresh from the same source as iOS.

So is the tab around it: `AndroidRootView`'s first tab mounts `SubmissionsTabView`, as
`LoggedInView` does. It hides the navigation bar and floats the "…" control
(`SubmissionsFeedActionView`) over the top-trailing corner on the glass surface — on
Android an opaque M3 `surfaceContainer` under a 3 dp shadow ([forks.md § The feed-gaps
patches](forks.md#the-feed-gaps-patches)). Only Explore is left out: `ExplorationView`,
the mode switch and the filters sheet are fenced `#if !FA_SKIP_MODULE`, as is
`@Namespace`, which SkipSwiftUI marks unavailable. Every floating control goes through
`floatingGlass` (`View+floatingGlass.swift`), which on Android in dark mode adds a 1 pt
white shadow, since the surface's dark shadow vanishes over dark artwork.

Re-tapping the selected tab pops to the root and, once there, scrolls to the top.
Hiding the bar took away SkipUI's only other scroll-to-top gesture, tapping the bar, so
an Android-only arrow makes it discoverable: `ScrollToTopButton` fades in after 30 pt of
scrolling up and hides once scrolling stops for 2.5 s, turns down or reaches the top.
SkipUI has neither `onScrollGeometryChange` nor `onScrollPhaseChange`, so
`ScrollToTopReveal` reads the direction from one reference row's `minY` in the
`onItemFrameChanged` reports; a report moving it over 200 pt is a jump (the re-tap
scroll), not a scroll. Its tests run on iOS too.

The scroll-preserving refresh choreography (a zero-height `fetchTrigger` row whose
`onAppear` fetches, in a `ScrollViewReader`) **runs on Android too**: the pull fires
the trigger, the badge shows, the list holds its position. Across a real *prepend*
(scroll down, `am force-stop`, relaunch: the restore check prepends newer items) the
anchor row now moves for one transient frame, 30–50 ms, where it used to walk back to
the top over ~5 s; see [below](#withanimation-marks-the-whole-frame-process-wide).

Opening a submission and coming back, or switching tabs, returns the feed to the same
row and offset. Compose saves only an index, and the list's safe-area header arrives a
pass late, so the feed used to come back one row lower ([forks.md § The feed-gaps
patches](forks.md#the-feed-gaps-patches)).

`ListItemTracking` **runs on Android too**, with no `#if`. It writes
`Defaults[.lastViewedSubmissionID]` as rows cross 30% from the top, and that value is
the server-side pagination anchor, not a scroll offset: the first fetch after launch
requests `msg/submissions/new~<sid>@72`, so the list renders from its natural top. It
measures rows with `onGeometryChange` in `.global`, since
`View.coordinateSpace(.named:)` is **absent from the SkipSwiftUI façade**, and
`GeometryProxy.frame(in: .named(…))` compiles and is **silently wrong** (it returns the
`.local` frame). Only `.local` and `.global` are real.

What Android gives up:

| Piece | On Android |
|---|---|
| `scrollView` + `.introspect(.scrollView…)` | Fenced `#if !FA_SKIP_MODULE`. The two reads sit behind `waitForPullToSettle()` and `scrollViewIsAtTop`, so no `#if` reaches the refresh logic. |
| `waitForPullToSettle()` | Returns immediately: Compose retracts its own indicator, so the spinner retracts before the fetch finishes, and the badge is the completion feedback. |
| `scrollViewIsAtTop` | Derived from the first row's `minY` in the frame reports (`trackFirstItemTop`), so foreground autorefresh skips on scroll position as on iOS. It is cleared by a change of the first id and by any later row reporting `minY < 32` (SkipUI's minimum row height), because after a restore the prepended head reports "at top" once and is then recycled silently. |

**Swipe-to-delete commits at the end of the swipe** on Compose, where iOS reveals a
Delete button. So Android *stages* the deletion (`Model.stageSubmissionPreviewsDeletion`,
through the shared `StagedDeletion`) and shows Material's Undo snackbar
(`StagedDeletionUndoSnackbar` around the shared `UndoSnackbar`). The `POST` goes out
after the timeout, when the feed disappears or the app backgrounds, or when another row
is staged; staged rows are filtered out of every fetch until then. iOS goes through the
same stage-then-commit code, committing at once, with no snackbar.

The snackbar is accessible the way Material's is. Its 5 s become
`AccessibilityManager.getRecommendedTimeoutMillis(5000, FLAG_CONTENT_TEXT |
FLAG_CONTENT_CONTROLS)`, read at each stage (`FAAccessibilityBridge.kt`): the user's
"Time to take action", or TalkBack's 10 s. Below API 29 it waits indefinitely while
touch exploration is on, as Compose's does (untested: the only emulator is API 37). It
is a polite live region (`.accessibilityAddTraits(.updatesFrequently)`) only while
shown, since a live region that hides is read again. Measured: 5.3 s with the setting
unset, 30.2 s at 30000, 10.1 s under TalkBack, which speaks "Submission deleted. Undo"
once.

The empty feed is reached with the login screen's "Continue offline, empty (debug)".

### `withAnimation` marks the whole frame, process-wide

On iOS a `withAnimation` transaction reaches only the state written inside it. On SkipUI
it sets a **static** marker cleared only on the next Compose frame, so *every* view that
recomposes in that frame animates. For a `List` that means a prepend animates row
placement, and `ScrollViewProxy.scrollTo` becomes `animateScrollToItem`. That is what
made the feed slide after a refresh. **Use `.animation(_:value:)`**, which is scoped to
one subtree. Anything on a hot path must not use the global form: the image fade on every
thumbnail arrival was the second offender, and Kingfisher's `ImageBinder` the third (the
fork moves it to `.animation(_:value:)`).

**Key `.animation(_:value:)` on a value Kotlin can compare.** SkipUI installs the
animation only on the composition where `value` differs from the remembered one. Keyed
on a **Swift enum** it silently never fires; `value: phase == .shown` does. Keep keys to
`Bool`, `Int` or `String`, and prove a new animation with a deliberately slow duration
first: at 0.35 s, animating and snapping differ by 10 frames. Capture on a quiet host,
after a warm-up launch.

**`.transition(…)` works under one contract**: the transitioning view must be an
`.id`'d child of an `HStack`/`VStack`/`ZStack`, and the stack itself carries the
`.animation(_:value:)`. With any un-id'd child the stack composes a plain `Box` and
nothing transitions; an `.animation` on the child never reaches it either.
`NotificationOverlay` and `CloudflareResolutionOverlay` are the worked examples:

```swift
ZStack {
    if let itemCount {
        badge(itemCount)
            .id("badge")            // constant: a new count updates in place
            .transition(.fallAndFade)
    }
}
.animation(.easeInOut(duration: 0.35), value: itemCount != nil)
```

During an exit the stack holds its size for a fixed 0.35 s, not the animation's own
duration, so a slower exit jumps sideways once that runs out.

**State-driven `.opacity`, `.offset` and `.scaleEffect` also animate from a scoped
animation**, which suits a view that stays mounted, like `ScrollToTopButton`. Since the
animation-resume patch ([forks.md](forks.md#why-skip-ui--skip-fuse-ui-are-forked)) an
animation interrupted by a `List` row recycling resumes at the right point.

## Submission screen

Tapping a feed card pushes the same `RemoteSubmissionView` → `SubmissionView` the iOS
app draws, with `RemoteView`, `SubmissionPreviewView`, `SubmissionControlsView`,
`SubmissionMetadataView` and all of `Comments/` shared verbatim. Ported: the image, the
zoomable viewer, favorite (with the `UpdateHandler` rollback), Save, Share, the
description with in-app links, threaded comments with the deep-linked one's highlight,
comment posting, "Send a Note", and the metadata screen.

Comment posting needed two things from the forks: `.glass` / `.glassProminent` and
`buttonBorderShape`, drawn as their bordered counterparts, and a sheet whose `content`
is only called while presented (`Replying`'s `fatalError()` guard crashed on the extra
calls).

`SubmissionMainImage` is shared, and so is its loader, one `configure(_:geometry:)` chain
over `KFImageProtocol`; one `#if FA_SKIP_MODULE` seam is left, the viewer's content,
where iOS's pixel sizing feeds its zoom ratios. The download-progress bar is shared too
(see [images.md](images.md)). `AlignedLabel`'s optical nudges go through
`symbolOpticalOffset(y:)`, a no-op on Android, where Material icons centre their glyph.

### The viewer

The viewer is presented from `fadingSheet` on both platforms: **a single tap** toggles
fill/fit, **pulling down** dismisses it, and system Back closes it. The pull is the
presentation's own, `ModalBottomSheet`'s here, which takes `.sheet`: SkipUI passes
`sheetGesturesEnabled: !(isFullScreen || interactiveDismissDisabled)`, so
`fullScreenCover` switches the pull off.

`Zoomable` still owns the *negotiation* iOS gets free between `UIScrollView` and the
sheet, through `.interactiveDismissDisabled`. Ownership is decided at the first drag
event with a direction, ahead of Material3's ~8 dp slop, and never revised mid-gesture:
the sheet gets only a downward, vertically dominant drag with no pan room left; a pinch
claims the gesture; everything else is the content's, and the sheet is then locked out
for that gesture. A `sheetOwnsDrag` latch makes the content ignore the drag the sheet
does get.

The backdrop does **not** fade to reveal the page: SkipUI's sheet container paints an
opaque grey and `presentationBackground` is unavailable, so Compose's scrim does the
reveal. The accepted cost of `.sheet`: an 18 pt band at the top, 16 pt rounded top
corners, and a **640 pt width cap** in landscape and on tablets. Undoing all three is
dropping `isFullScreen ||` from that line in `Ceylo/skip-ui` and presenting with
`fullScreenCover` again.

Inertia and edge behaviour are hand-built. Releasing a pan runs Android's `OverScroller`
spline, its closed forms reconstructed in Swift, with a velocity timed by hand because
SkipUI builds every `DragGesture.Value` with `velocity: .zero`; Compose's 100 ms
staleness window applies at the release too, or "pan, hold still, lift" would fling. At
a bound the pan continues with resistance and a critically damped spring brings it back,
as Android's image viewers do; flings stay clamped. The viewer resets offset and zoom on
each presentation, and re-derives the initial zoom from **every** viewport measurement
until the user first adjusts it, since the sheet first reports a height ~129 px short.

### Stories and music

A story's cover, download and Save/Share come from the shared `SubmissionTextContent`.
Only the reader is forked: `StoryReaderView` builds its `Content` through
`StoryReaderView.Content.load(data:filename:documentUrl:)` on both platforms. The
Android reader shows txt and md from FAKit's `StoryText`, one `Text` per line in a
`LazyVStack` so Compose never measures a whole novel at once; other formats get "Open in
another app" (`FAMediaBridge.open`).

Music has an Android `SubmissionAudioContent` with the iOS signature: the cover, and
"Play in another app", which downloads the mp3 and hands it over; Save/Share light up
once downloaded. It downloads only when asked, unlike iOS: the page transport can't
cancel an exchange and holds a permit for the whole transfer.

Not ported, each an Apple-only stack: in-app playback and lock-screen controls,
pdf/rtf/docx reflow, the QuickLook "Original" view and the reader's landscape gate.

A download still challenged after the repair fails instead of taking the WebView
fallback, which reads back a page and so never returns a file.

### Android-only substitutes

Each keeps the iOS name and signature so shared callers compile unchanged: `HTMLView`,
`Zoomable`, `FlowLayout`, `MediaSaveHandler`, `fadingSheet`
(`View+pullableScreenCover.swift`), `StoryReaderView`, `SubmissionAudioContent`, and the
no-ops in `SubmissionShims.swift`.

`HTMLView` does real work: `FAKit` normalises FA's markup (`FAHTMLNormalizer`) and
Compose parses it (see `Text(html:)` under [the other fork
patches](forks.md#the-other-fork-patches)). `fromHtml` reads neither `<style>` nor
classes, so the normaliser restates the theme rules that show, for `FATheme.current`:
quotes in `<i>` with their name in `<b>`, and in dark only, headings in `#add8f5` and
description links in `<b>`. An element's own `color` wins. Links keep the app tint and
spoilers stay visible. The rules are copied by hand from `ui_theme_dark.css` and
`ui_theme_light.css`; an iOS test pins them to the bundled sheets, so follow a restyle of
FA's by hand. The view puts back what the parser drops: a `Divider()` per `<hr>`, and an
inline view at each `<img>`'s U+FFFC. The text never waits for an image: each is sized
from its `width`/`height`, else a fallback (50×50 avatar, 19×19 smilie), then from its
own size once `FAImage` loads it, capped at 50×50 for avatars and the text width for all.
Accepted losses, none exercised by FA's corpus: `<ol>` numbering, `<blockquote>` indent,
`<code>` monospace, px font sizes, `<sub>` size, exact heading sizes. GIF avatars stay on
their first frame. Its padding is 3 dp vertical and **8 dp horizontal**, matching iOS,
whose `UITextView` adds `lineFragmentPadding = 5` to the 3 pt inset.

Link taps never reach `openURL`: Compose hands them to `onLinkTap`, which pushes anything
`FATarget(with:)` matches into `NavigationStream` through `MainActor.assumeIsolated` (a
`Task` hop would defer it a frame) and sends the rest to the browser.
`view(for:)` lives in `InAppNavigation+Android.swift`.

### Scrolling to a deep-linked comment

The shared `scrollToItem` needed two fork fixes: a `ViewModifier`'s `content` used to be
a JNI *local* reference, so deferring it into the `ScrollViewReader` closure aborted
("jobject is an invalid JNI transition frame reference"; look for
`SwiftBackedFunction*.invoke` if it returns), and the proxy now resolves the `List`'s
scroll action at call time rather than at first composition. The anchor is still
ignored: SkipUI brings the row to the top, where iOS centres it.

To reach a deep link without a notification, launch a debug build with `--es faOpenURL
<url>`; `AndroidRootView` opens it once there is a session:

```
adb shell am start -S -n <app id>/fur.affinity.ui.MainActivity \
  --es faOpenURL "https://www.furaffinity.net/view/48519387/#cid:166652794"
```

### Save and Share

`FAMediaBridge.kt` inserts images into MediaStore's `Pictures/FurAffinity` and documents
into `Download/FurAffinity`, and starts `ACTION_SEND` (Share) and `ACTION_VIEW` (Open in
another app). "Save to Files" saves without asking where, and a toast says where it went
or that it failed. Staged hand-off files in `cache/shared` expire after an hour, since a
player re-opens the URI to seek, and are written under a temporary name and renamed, so
such a reader keeps its inode. On API 28 Downloads falls back to the share chooser. The
manifest must carry, and a regeneration easily loses:

- the `androidx.core.content.FileProvider` `<provider>` with
  `${applicationId}.fileprovider` and `@xml/file_paths`: shared files sit in the app
  cache and go out as `content://` URIs;
- `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="28"`, needed by the MediaStore insert
  before scoped storage.

`cachedImageFileURL(for:)` first copies the bytes out of Kingfisher's disk cache, whose
entries have **no extension**, to `tmp/fa-media/<UUID>/<remote filename>` (see
[images.md](images.md)). `temporaryDirectory` needs no platform branch: Skip's
`AndroidBridgeBootstrap` points `XDG_CACHE_HOME` at `context.cacheDir`, which
`@xml/file_paths` exposes.

## Notifications

The tab is the iOS one: `RemoteNotificationsView`, `NotificationsView`, the three row
views and `NotificationsActionView` (the floating "…" nuke menu and its alerts) build for
both platforms. `AndroidRootView` gives it its own `NavigationStack` path, as
`LoggedInView` does, so a link pushes onto the selected tab's stack (Settings, which has
none, sends it to Submissions). The badge is `Model.displayedNotificationCount`, set by
the "Tab Badges" settings, which Android shows without the delivery section.

Swipe-to-delete works as in the feed: a full swipe stages the deletion
(`Model.stageNotificationsDeletion`) behind the same snackbar, and iOS commits at once.
Each staged row keeps its section and index, so Undo, or a send that fails, puts it back
where it was; a fetch leaves staged and in-flight rows out. A nuke commits a staged batch
first.

A journal or journal-comment row opens the **journal screen** (`RemoteJournalView`),
shared too: it reuses the submission screen's `HTMLView`, comments, comment and note
sheets. A shout row or an avatar opens a user page, which is not ported and shows the
placeholder.

The empty state ("Continue offline, empty (debug)") is `Text(markdown:)`, which on Android
goes through `LocalizedStringKey`, since Android's Foundation has no
`AttributedString(markdown:)`.

## Notes

Material has no circled filter icon, so the unread filter's button looks the same on and
off; only its accent tint says the filter is on.
