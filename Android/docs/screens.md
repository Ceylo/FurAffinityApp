# Screens

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

The empty feed is reached with the login screen's second debug button, "Continue offline,
empty (debug)" (`AndroidRootView`), which signs in with `OfflineFASession.empty` — no
submissions, so `model.submissionPreviews` is `[]` and the feed mounts its `noPreview`
placeholder for real rather than as a mock.

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
patch (see [Why skip-ui / skip-fuse-ui are forked](forks.md#why-skip-ui--skip-fuse-ui-are-forked))
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

`SubmissionMainImage` itself is now *shared*, with `#if FA_SKIP_MODULE` around only the
loader and the viewer's content. The viewer is presented from `fadingSheet` on both
platforms, and behaves the same way: **a single tap** toggles fill/fit (matching iOS's
`numberOfTapsRequired = 1`), and it is dismissed by **pulling it down** rather than by a
close button. The system Back gesture still closes it.

The pull is the presentation's on both platforms — `UISheetPresentationController`'s on
iOS, `ModalBottomSheet`'s here. Getting Compose's took presenting with `.sheet`: SkipUI
draws `sheet` and `fullScreenCover` as the same `ModalBottomSheet`, but passes
`sheetGesturesEnabled: !(isFullScreen || interactiveDismissDisabled)`, so
`fullScreenCover` is precisely what had switched the pull off and made `Zoomable` grow a
hand-rolled one.

What `Zoomable` still owns is the *negotiation* iOS gets free between `UIScrollView` and
the sheet: `.interactiveDismissDisabled(maxOffset(in:).height > 0.5)`, a preference SkipUI
feeds straight to `sheetGesturesEnabled`, so vertical drags belong to the content exactly
while it has somewhere left to pan and to the sheet once it hasn't. A `sheetOwnsDrag`
latch then makes the content ignore the whole of a drag the sheet owns — the horizontal
component included, or it drifts sideways while the sheet travels down.

The backdrop deliberately does **not** fade to reveal the page: SkipUI hands
`ModalBottomSheet` a `Color.Unspecified` container that paints an opaque grey, and
`presentationBackground` is `@available(*, unavailable)` in skip-fuse-ui, so a fade
reveals that grey rather than the submission. Compose's own scrim does the reveal instead.

Accepted cost of `.sheet` over `fullScreenCover`, weighed and kept: an 18 pt band at the
top (`presentationDragIndicator(.hidden)` suppresses the capsule but keeps its footprint)
showing the scrimmed page, 16 pt rounded top corners, and `BottomSheetDefaults`'
**640 pt width cap**, which boxes the viewer in landscape and on tablets. Undoing all
three is one line in `Ceylo/skip-ui` — dropping `isFullScreen ||` from that
`interactiveDismissDisabled`, then presenting with `fullScreenCover` again.

A `UIScrollView` gives the iOS viewer inertia and edge behaviour for free; here both are
hand-built. Releasing a pan runs Android's `OverScroller` spline — its closed forms
reconstructed in Swift, since a Skip Fuse module has no Compose to borrow `splineBasedDecay`
from — and the velocity that launches it is timed by hand from successive translations,
because SkipUI builds every `DragGesture.Value` with `velocity: .zero`. Compose's 100 ms
staleness window is applied at the release as well as between samples: a finger that stops
moving stops producing events, so the sampler never sees the pause on its own and the
pre-pause velocity would otherwise fling.

At a bound the pan continues past with resistance and a critically damped spring brings it
back, which is what Android's *zoomable image viewers* do (Google Photos, telephoto). It is
deliberately not the Android-12 stretch overscroll: that is a scroll container's own edge
effect, and there is no scroll container here. Resistance is a hyperbolic falloff — ~55% of
the finger's travel gets through just past the bound, and the excess asymptotes at the
viewport's own extent, so the content can never be pulled clear of the viewport. Flings stay
clamped, so one that reaches a limit simply arrives; only a drag can overscroll.

The viewer also resets itself on each presentation — offset and zoom — because skipstone
backs `@State` with `rememberSaveable`, which otherwise restores whatever the last
presentation was left in. The initial zoom is re-derived from **every** viewport
measurement until the user first zooms or pans (`hasUserAdjusted`), not latched on the
first one: the sheet reports a height ~129 px short of its final one before its insets
settle, and `boundedFill` computed from that left the image visibly letterboxed where
`fullScreenCover` had filled the screen.

Deferred, with the reason:

| Not ported | Why |
|---|---|
| Comment posting, note sending | The `CommentEditor`/`NoteEditor` UI isn't ported. Android passes `replyAction: nil` / `acceptsNewReplies: false`, so the swipe/context reply paths are inert. (`Replying`'s storage is now `@Observable`, not `ObservableObject`, so the machinery around the editors is no longer the blocker.) |
| Story (`.text`) and music (`.audio`) submissions | `StoryDocument` (PDFKit reflow, DOCX, QuickLook) and AVPlayer + `MPNowPlayingInfoCenter` are Apple-only stacks. Both render a placeholder with a link to the file. |
| `scrollToItem` (scroll a deep-linked comment into view) | see below |

### Android-only substitutes

Each keeps the iOS name and signature so symlinked callers compile unchanged:
`HTMLView`, `Zoomable`, `FlowLayout`, `MediaSaveHandler`, `fadingSheet` (the iOS one
crossfades a UIKit-backed `.sheet`; `View+pullableScreenCover.swift`),
`SubmissionTextContent`/`SubmissionAudioContent`, and the no-ops in
`SubmissionShims.swift`.

`HTMLView` is the one that does real work rather than standing in. iOS renders FA's rich
text through WebKit's HTML importer into a `UITextView`; here `FAKit` normalises the
markup (`FAHTMLNormalizer`) and Compose parses it — see `Text(html:)` under
[the other fork patches](forks.md#the-other-fork-patches). The view itself only puts back what
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

Link taps inside rich text never reach `openURL`: Compose hands them to this view's
`onLinkTap`, which pushes anything `FATarget(with:)` matches into `NavigationStream` and
sends the rest to the browser. The listener fires on the Compose UI thread, so it reaches
the (main-actor) stream through `MainActor.assumeIsolated` — a `Task` hop would defer the
push by a frame. Nothing rewrites URL schemes on either platform any more; Android
registers no scheme at all, and `appNavigationScheme` (`InAppLinkConversion.swift`)
survives only as iOS's external entry point.

`view(for:)`, the half of `InAppNavigation.swift` that can't be shared at all (it names
screens that don't exist here), lives in `AndroidNavigationDestination.swift`.

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
