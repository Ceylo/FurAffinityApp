# Forks

| Fork | Why |
|---|---|
| `Ceylo/Defaults` | Android port; `Defaults.defaultSuite` (see [Defaults](shared-sources.md#defaults)) |
| `Ceylo/skip-ui` | `listRowInsets` (and innermost-wins `listRow*` precedence); resuming an in-flight animation across composition disposal; a `ScrollView` that fills its scrolled axis; `Text(bridgedHTML:…)`; `Text(bridgedRichText:bridgedInlineViews:)`; `Text(bridgedSegments:…)`; `FlowRow`; a `GeometryReader` composed on the measure pass that still answers intrinsic queries; a draw-phase `ImageHolder`; springs that are springs; `.id` state reset scoped positionally rather than by swapping the state saver; geometry that reports a view's laid-out frame rather than its clipped one; SF Symbol mappings; iOS-parity text layout (HTML line height, `.subheadline` weight, menu text/icon size, menu divider) |
| `Ceylo/skip-fuse-ui` | the Fuse side of each: `listRowInsets`, `Text(html:…)`, `Text(AttributedString)` / `Text(_:inlineViews:)` (disfavoured, so literals still localize), `Text.+`, `FlowRow`, `Image(holder:)`, plus `glassEffect`/`GlassEffectContainer`/`AnyTransition.animation` un-`unavailable`d; `#Preview` / `@Previewable` stubs (skiptools/skip#439) |
| `Ceylo/Kingfisher` | Android port: platform guards, a decode seam onto SkipSwiftUI's `UIImage`, a bridgeable SwiftUI layer, and a rendered image that comes out of an `ImageHolder` rather than out of the view value |
| `Ceylo/skip-web` | dependency identity only: it must name `Ceylo/skip-ui` and `Ceylo/skip-fuse-ui`, no source changes |

Sending any of these patches back to its origin project — the gates each project sets, what
its own merged and rejected PRs show, and the shape a PR must take — is
[upstreaming.md](upstreaming.md).

All on an `android` branch, referenced by URL + branch from `Package.swift` (and, for
Defaults and Kingfisher, the Xcode project too). While iterating, re-point the root
`Package.swift` at a local clone:

```
.package(path: "../../SkipForks/Defaults")     // instead of the URL + branch
```

The clone's directory must carry the repo's name: SwiftPM takes the package identity from
the last path component, so `skip-fuse-ui-preview/` would clash with the URL every other
package names. Then push to the `android` branch before the step's gate.

The root `Package.resolved` **is** committed (`.gitignore` carries a `!/Package.resolved`
negation), as is the Xcode workspace's copy; only `FAKit/Package.resolved` stays ignored.
Five deps resolve from mutable `branch: "android"` refs, so without the recorded
revisions a release APK isn't reproducible. Refreshing a fork is
`swift package update <dep>`, followed by committing the resulting diff. The root
manifest declares swift-syntax, unused, only so that update keeps the pin that
skip-fuse-ui's Android-only `#Preview` macro needs. That macro costs about 45 s on a
clean Android build — swift-syntax builds from source, the swift.org toolchain has no
prebuilts — and nothing incrementally.

**`android` is never rebased or force-pushed**: the revisions committed above must stay
reachable. To pick up upstream — including a fork patch that has since merged there —
fast-forward the fork's default branch to upstream's, then merge it into `android`,
resolving the merged patch in upstream's favour. Kingfisher `239c970b` is the example.

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

## Why skip-ui / skip-fuse-ui are forked

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

A fourth patch, to `Containers/ScrollView.swift`, gives the scrolled node its axis.
`.refreshable` is `Modifier.pullRefresh`, and Compose's `pullRefresh` is purely a
nested-scroll connection: it sees only the deltas a scrollable child dispatches, so the
pull is accepted exactly over the scrollable node's bounds. Only the container `Box`
filled; the scrolled `Column` stayed at content size. On the Followed feed's empty
placeholder that meant pull-to-refresh worked over the text and nowhere else, where
`UIScrollView` takes the gesture across its whole frame — and a fling started below short
content was ignored outright. `RenderList` already avoids this with `fillMaxSize()` on the
`LazyColumn`; the patch does the same, filling the scrolled axis *before* applying
`verticalScroll` / `horizontalScroll`. Taller-than-viewport content is a no-op —
`verticalScroll` still measures with `maxHeight = Infinity` — and short content is visually
unchanged, the `Box` having filled and aligned `TopStart` already. One behavioural
side effect, shared with `List` today: a short page in a large-title `NavigationStack` now
has the title's worth of scroll range, so an upward drag can collapse the large title where
iOS would keep it.

A fifth patch is one attribute, and it is a caution about the four above: adding an
overload to `Text` can silently capture *string literals*. `Text(AttributedString)` — our
own addition — went in without `@_disfavoredOverload`, and `AttributedString` is
`ExpressibleByStringLiteral`, so a plain `Text("…")` preferred it over
`init(_ key: LocalizedStringKey, tableName:bundle:comment:)`. Every literal in the app then
took the rich-text path, which never reaches commonmark, and implicit markdown —
`**bold**`, `[link](url)`, `` `code` `` — rendered verbatim everywhere (literal
localization lookup went with it). The Followed feed's empty placeholder is where it
showed. Only *bare* literals were affected: `Text(String("…"))`,
`Text("…" as LocalizedStringKey)` and `Text("…", tableName: nil)` all resolved correctly,
and that literal/non-literal split is the fingerprint to look for — the render chain
converges and tells you nothing. `Text` is `Equatable` over its `TextSpec`, so
`Text("…") == Text(AttributedString("…"))` settles which overload won. Any new `Text`
initializer whose parameter is expressible by a string literal wants
`@_disfavoredOverload`, as `init<S: StringProtocol>` and
`init(_ resource: AndroidLocalizedStringResource)` already carry.

A sixth patch, to `Layout/GeometryReader.swift`, makes the content composable on the
*measure* pass. It composed a `Box` with `onGloballyPositionedInRoot` and rendered
`content(proxy)` only once that callback's state write had scheduled a recomposition, so
every `GeometryReader` in the app drew nothing on its first frame — SwiftUI, by contrast,
hands its content a size on the first pass. `BoxWithConstraints` composes during measure,
and since the modifier is `fillSize()` bounded constraints already *are* the final size, so
the proxy is exact straight away. Only the global *origin* is late: `frame(in: .global)`
reads (0, 0) until placement delivers the real rect one recomposition on, which is why the
remembered rect stays and still wins once it exists. Where either axis is unbounded — a
`GeometryReader` inside a scroll axis — the constraint is `Constraints.Infinity`, a worse
answer than none, so there the old wait-for-placement behaviour stands.

Measured at `SubmissionPreviewView` → `SubmissionView`, where the cost was most visible:
`SubmissionMainImage`'s body ran 616–689 ms before its `GeometryReader` composed anything,
and a `.background(.red)` probe showed the row fully laid out — header, title, correct
aspect-ratio height — over a solid red image area. After the patch that gap is 263 ms of
composition→measure latency, which draws nothing because nothing is drawn before measure
completes. The one caveat is cost:
`BoxWithConstraints` is a `SubcomposeLayout`, heavier than a `Box`, and `GeometryReader` is
on the feed-card path.

That patch also introduced a crash, fixed since. Compose throws on any intrinsic query to a
`SubcomposeLayout` ("Asking for intrinsic measurements of SubcomposeLayout layouts is not
supported"), and SkipUI does ask: `ComposeFlexibleContainer` gives a height-filling container
`height(IntrinsicSize.Max)` along an inherited scroll axis, and `ViewThatFits` measures
intrinsics too. Upstream's `Box` answered from its content. So `SubmissionMainImage`'s
progress bar, a `GeometryReader` in a `ZStack` over the thumbnail, crashed the app on its
first full-resolution load. The box now fills a `GeometryReaderLayout`, a plain `Layout`
that carries the reader's modifiers and answers all four intrinsic queries with 10 dp, without
measuring content. That matches SwiftUI, where a `GeometryReader` has no ideal size and
reports 10×10 pt under an unspecified proposal. In that `ZStack` the container comes out as
tall as the thumbnail and the reader fills it, as on iOS.

A seventh patch adds **a draw-phase image**. <a name="a-draw-phase-image"></a>
`ImageHolder` is a bridged reference type over a `MutableState<Bitmap?>`;
`Image(bridgedHolder:)` renders it through an `ImageHolderPainter` that reads the bitmap in
`onDraw`. Writing to a holder repaints without recomposing, so an image resolved at any
point before a frame's traversal is painted in *that* frame, and because the node is
composed from the first pass and simply draws nothing until the holder is set, it never has
to be swapped in for a placeholder — there is no pass in which one is gone and the other not
yet painted. `ImageLayout` takes the intrinsic size as a closure now, evaluated inside the
measure block, so sizing is a layout-phase read too; an unspecified size fills the offered
space, as `RenderPainter`'s `fillSize()` branch already did. skip-fuse-ui vends it to native
Swift as `Image(holder:)`. Kingfisher is the caller — see
[§ Why Kingfisher is forked](#why-kingfisher-is-forked).

Verified on the emulator with frame boundaries marked by a self-reposting
`Choreographer.postFrameCallback` — `screenrecord` drops a single frame, so it is not the
instrument. A memory hit logs `COMPOSE renderable=false` → `setImage` → `DRAW` inside one
frame, with the recomposition that reports it renderable only in the next; on
`SubmissionView` the composition that releases the thumbnail and the draw of the
full-resolution image fall in the same frame.

Moving the *write* instead — running `onAppear` during composition — lands in the same frame
too, and was measured doing so, but it would run arbitrary caller side effects in a pass
Compose may discard or replay, and this app's `onAppear`s are exactly the ones that must not
double-fire (`RemoteView` starts the page fetch in one, `SubmissionsFeedView` a refresh
`Task` in another). Moving the read costs nobody anything.

An eighth patch, to `Animation/Spring.swift`, makes **springs springs**.
`Spring(duration:bounce:)`, `Spring(response:dampingRatio:)` and
`Spring(settlingDuration:…)`, and so `.spring`, `.smooth`, `.snappy`, `.bouncy` and
`.interactiveSpring`, were all a 500 ms-ish `TweenSpec` eased with `EaseInOutBack`. That
curve first moves *away* from its target for about a third of its run, and a value
retargeted faster than that restarts it from wherever it is. The progress bar's width,
retargeted every ~100 ms, was negative in 290 of 822 frames, and a negative frame draws
nothing: `.animation(.spring, value:)` looked like it painted nothing at all. Each
initializer now builds a unit-mass `SpringSpec`, as `Spring(mass:stiffness:damping:)`
already did. Stiffness is (2π / response)². `duration`/`bounce` use SwiftUI's own
mapping, and `settlingDuration` solves the decay envelope for ω. `snappy` and `bouncy` get
their SwiftUI base bounce (0.15, 0.3). `speed(_:)` scales stiffness by speed², and
`delay(_:)` wraps the spring in a `DelayedAnimationSpec` (`Skip/DelayedAnimationSpec.kt`),
because Compose's delays exist only on tweens and `StartOffset`. `repeatCount` and
`repeatForever` still leave a spring alone, since Compose repeats only duration-based specs.

A ninth patch, to `View/AdditionalViewModifiers.swift`, is the *third* patch's subject seen
from the other side: the same `LazyColumn` recycling boundary, but the state that **does**
survive it. `TagModifier` handed a `.id` subtree a brand new, empty `ComposeStateSaver`
whenever the id value changed (upstream `4ed8380`, "Fix .id to reset state when it
changes", #330). A `ComposeStateSaver.Key` is nothing but a lookup token into the `state`
map of the saver that minted it, so a descendant's saved entry stops resolving the moment
the saver is replaced. `restore` returns nil, and Compose's `mutableStateSaver` wraps an
inner nil in a *non-null* `MutableState`, so `rememberSaveable`'s `restored ?: init()`
never fires and the nil escapes into the subtree. For a bridged `@State` that is fatal:
skipstone generates `Swift_syncState_x(peer, remembered.value)` with no null check and
`StateSupport.fromJavaObject` force-unwraps, so the process aborts on
`StateSupport_Bridge.swift:11`.

Kingfisher is the caller that hit it, because `KFImageProtocol.body` is
`ZStack { KFImageRenderer(context:).id(context) }` and `KFImage.Context` is `Hashable` over
`(source, processor.identifier)` — **the image URL is the `.id`**.
`SubmissionFeedItemView` derives that URL from the live `GeometryReader` size through
`DynamicThumbnail`'s buckets (200/300/320/400/600 dp), so anything that moves the measured
size across a boundary moves the id.

Three ways an entry reaches the wrong saver, only the first of which needs the id to
return: an id going back to an earlier value reproduces that value's composite key hash and
consumes an entry `SaveableStateRegistryImpl.performSave` has been re-emitting since an
earlier incarnation; an id going A→B where B was used before does the same; and a row
disposed right after a reset pass saves *through* the fresh saver — `SaveableHolder.update`
is a `SideEffect`, so descendants keep it as their save-provider until the next
composition — into a saver that is then garbage.

The swap was never needed for the reset it was added for.
`GapComposer.updateCompositeKeyWhenWeEnterGroup` folds a movable group's `dataKey.hashCode()`
into `currentCompositeKeyHashCode`, which is exactly what `rememberSaveable` keys on, so the
`key(idValue)` already in `TagModifier` resets saved state as well as remembered state. What
it does not do is separate one incarnation of an id from the next. So the patch drops the
swap — every descendant now sees the one long-lived ancestor saver that minted its keys —
and keys on an id *generation* alongside the value: a counter, itself `rememberSaveable` and
living outside the `key()`, bumped whenever the remembered id differs from the current one.
An `Int` passes through `ComposeStateSaver.save` verbatim, so it is genuinely Bundle-safe,
and the remembered id is typed `Any?` so that a restore returning nil counts as a change
instead of failing an unwrap. `role == .id` guards all of it, so `.tag` (`Picker`,
`TabView`, `Menu`) is untouched.

### Why the emulator hid it, and a Galaxy S25 did not

The crash arrived from a tester who reported nothing but scrolling — no zoom setting, no
split screen, no rotation. The first repro needed `wm density` flips while flinging, which
looked like a different bug, and it is not: `bestThumbnailUrl` buckets on `maxDimension`
*after* fitting into 600x600, so the row's **width in dp** sets a floor. The emulator's
1080 px at 420 dpi is 411 dp, and 411 selects `s600` for every row whatever its height — so
scrolling could not move the id there, and 60 fling cycles logged zero id changes. A Galaxy
S25 is 1080 px at 480 dpi, i.e. **360 dp**, and at 360 the floor no longer swallows the
height: a row measuring 400 dp or less picks `s400`, a taller one `s600`.

Clipped is the operative word. SkipUI reported a partially-visible `LazyColumn` row's
*clipped* size to its `GeometryReader`, the same truncation that pinned a clipped row's `minY`
to 0 — both since fixed by the [tenth patch](#a-tenth-patch-laid-out-frames), which is
why plain scrolling no longer moves the id at all. A feed row whose aspect ratio asks
for 360x505 dp logged 360x415 dp, then 360x351 dp, then 360x45 dp as it left the viewport —
so at 360 dp **plain scrolling** walks its id back and forth across a bucket boundary,
several times per fling. Setting the emulator to `wm density 480` and flinging reproduced
the tester's crash with no density change at all, 3/3 inside the first scroll cycle — every
`restore` miss followed on the next log line by the abort. Nothing about the fix depends on
that, but it is the regression test: the density flip was only ever the cheapest way to
fake it. After the patch, 3/3 runs survived 40 scroll cycles with 1671 id changes, 5886
restore hits and 0 misses, over 3 saver instances rather than one per change.

### What this does not fix

**Process death and restore.** The Bundle returns the `Key`; the in-memory map does not, so
`restore` must return nil, and `mutableStateOf(null)` defeats `restored ?: init()` the same
way. That is not `.id`-specific and cannot be fixed from this fork — it wants a null check
in skipstone's generated `syncState` call,
`Swift_syncState_x(peer, remembered.value ?: Swift_initState_x(peer))`. The app dodges it in
practice: a killed process cold-starts through `RootView`/autologin, so the feed's slots
never restore.

One thing to watch: an A→B→A toggle reused `hash(A)`'s registry entry before and now writes
a new one per id change, so the registry grows where it used to alias. It is not visible at
this app's scale — measured over 60 fling cycles, the Java heap grew **less** in the
heavy-churn arm (34.1 → 29.2 MB at 480 dpi, ~2 id changes per fling) than in a no-churn one
(29.7 → 38.8 MB at 420 dpi, zero) — but `ComposeStateSaver.state` is never pruned at all
today, which is the larger version of the same question.

### A tenth patch: laid-out frames <a name="a-tenth-patch-laid-out-frames"></a>

The ninth patch removed the crash; the tenth removes its trigger. `GeometryProxy` holds one
rect and derives `size` and `frame(in:)` from it, and that rect — like every
`onGeometryChange` value — came from `onGloballyPositionedInRoot` in
`Compose/ComposeExtensions.swift`, which read `boundsInRoot()`. Compose defines that as
`findRootCoordinates().localBoundingBoxOf(this)`, and `localBoundingBoxOf`'s `clipBounds`
defaults to `true`: the rect is intersected with every clipping ancestor. It was in
SkipUI's first `GeometryReader` and never revisited — a default, not a decision. The patch
builds the rect from the node's own `size` and `positionInRoot()`, as SwiftUI reports the
laid-out frame whatever is scrolled over it. The zero-rect guard now means "not yet
measured", so an off-screen node reports its real off-screen frame instead of nothing.
`onGloballyPositionedInWindow` is left alone: its callers (safe area, tab and navigation bar
metrics) are full-screen nodes never inside a clipping scroll parent.

Real SwiftUI was checked first with the same probe: a `List` row's size stays constant
and its `minY` goes negative (down to −1368 pt). Then on Android, at `wm density 480` (360 dp):

| | before | after |
|---|---|---|
| rows reporting more than one size in a fling | 47 of 48 | 0 of 45 |
| `.id` changes after first appearance, 3×40 fling cycles | 1671 | 0 |
| extra-bucket thumbnail fetches, 40 flings down a cold feed | 10 (48 rows) | 0 |
| prefetched URLs no row used | 0 | 0 |

So the win is parity and the trigger, plus about one wasted thumbnail fetch per five rows
first scrolled into view. Prefetching was never void, and a frame-by-frame scan of a
warm-cache fling found no placeholder flash before the patch either. The app's two readers
of list-row geometry, `trackFirstItemTop` and `followItem` ([screens.md](screens.md)), now
see a negative `minY` like iOS; both kept their behaviour. `CommentsWidthMeasuring` and the
zoomable viewer ride the same helper and render as before.

### After upstream #500 <a name="after-upstream-500"></a>

Upstream #500 rewrote `GeometryReader` around a `GeometryReaderState` whose proxy observes
per property, so size-only content no longer recomposes when the reader moves. It took the
size from the measured `$0.size`, which fixes the clipped *size* its own way, but kept
`boundsInRoot()` for the frame (its `globalFrameReaderObservesMovementAndClipping` asserts
the clip) and went back to waiting for placement. The merge (`0a6d781`) keeps #500's state
and proxy, feeds the state the laid-out frame (`positionInRoot()` + `size`), and keeps the
measure-pass `BoxWithConstraints` inside `GeometryReaderLayout`: until the state is
positioned, content gets a fixed proxy seeded from the constraints, so nothing is written to
state during composition. `actualReaderReportsUnclippedGlobalFrame` pins the frame.

The same merge brought in one regression, undone in `7111bfa`. #500 renders a `.resizable()`
asset image whose Coil painter has no intrinsic size yet through `RenderPainter`, to spare a
cached icon its one-frame 0×0 placeholder. Without an intrinsic, `RenderPainter` fills, and the
layout outlives the load. `HomeView`'s `AppIcon` (`.resizable().aspectRatio(contentMode: .fit)
.frame(width: 100)`) took the whole height of its `VStack` and pushed the login buttons 646 px
down, over the footer. With that branch removed, the button bounds are back to the pre-merge
`[306,1324]` / `[459,1504]`.

## One location per identity

SwiftPM allows a package identity exactly one location across the whole graph, and
`Ceylo/skip-fuse-ui` forces the question: its `SkipSwiftUI.Text.Java_view` calls
`SkipUI.Text(bridgedHTML:)` and `Text(bridgedSegments:)` outside `#if SKIP`, so pairing
it with upstream skip-ui does not compile — on Apple either. **Every** manifest in the
graph therefore names `github.com/Ceylo/skip-ui`: the two skip forks and Kingfisher say
so themselves, which is the whole reason `Ceylo/skip-web` exists.

The app manifests must **not** re-declare skip-ui. A root declaration used to be how the
fork won, and it is what SwiftPM reports as *"dependency 'skip-ui' is not used by any
target"*; the other half of the same problem is *"conflicting identity for skip-ui"*,
naming whichever chain still points upstream. Both are warnings that SwiftPM says it will
escalate to errors.

Before the forks agreed, a third declaration of the identity could flip SwiftPM's
tie-break: the first resolve rewrote the workspace pin's *location* to
`source.skip.tools/skip-ui` while keeping the fork's revision, which then could not be
checked out, and left a half-written checkout that failed every later resolve with
"Package.swift doesn't exist in file system" — or, in `DerivedData/…/SourcePackages/`, a
gutted `checkouts/skip-ui` (only `.git` left) that aborts the resolve before the `skip`
binary artifact is unpacked, so the build dies on "ArtifactsArchive info.json not found
… skip.artifactbundle". Recovery, should a stale pin resurrect it: drop the offending
pins from the workspace `Package.resolved`, `rm -rf` that checkout and
`artifacts/skip`, and resolve again.

A branch pin is refreshed, not re-resolved: `xcodebuild -resolvePackageDependencies`
re-records the revision already pinned, so after pushing to a fork's `android` branch,
delete its pin (or `swift package update <dep>` at the root) rather than expecting the
resolve to pick the new head up.

Deleting the pin alone is **not** enough on the Xcode side, and the resolve reports the
old revision without complaining. SwiftPM keeps a third record —
`DerivedData/<proj>/SourcePackages/workspace-state.json` — whose `checkoutState` it trusts
over the branch, and it re-pins from there even when the mirror already has the new head
and the checkout has been deleted. The symptom is a resolve that keeps printing
`@ android (<old sha>)` while `git ls-remote` shows a newer one. All three have to go
together:

```
DD=$(xcodebuild -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILD_DIR =/{print $2}' | sed 's|/Build/Products||')
# 1. the pin, from FurAffinity.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# 2. the dependency's entry in "$DD/SourcePackages/workspace-state.json"
rm -rf "$DD/SourcePackages/checkouts/<Dep>"          # 3. the checkout
xcodebuild -project FurAffinity.xcodeproj -scheme FurAffinity -resolvePackageDependencies
```

This is how the workspace sat on `4f7ad45` while the root manifest was on `fb0ef04` — one
commit apart, on the same fork, for the two builds.

## Why Kingfisher is forked

Android reimplemented, in Swift and Kotlin, what iOS gets from Kingfisher for free: a
decoded-image LRU, fetch and decode coalescing, off-main decoding, disk staging with its
own expiry, and a KFImage-shaped view. A July 2026 attempt had concluded that
"Kingfisher's networking is coupled to its CoreGraphics/ImageIO image-decoding pipeline,
which can't compile on Android without gutting it."

The coupling is real but narrow. Every decode funnels through five entry points in
`Sources/Image/Image.swift`, and SkipSwiftUI's Bitmap-backed `UIImage` answers all of
them — `init?(data:scale:)`, `pngData()`, `jpegData(compressionQuality:)`,
`preparingThumbnail(of:)`. Substituting there is far cheaper than emulating
`CGImageSource`, and it avoids two traps a shim would walk into: `UIImage.init(cgImage:)`
and `.cgImage` are `@available(*, unavailable)` in skip-fuse-ui, and a module named
`ImageIO` or `CoreGraphics` would re-run the module-name poisoning in
[build-and-run.md](build-and-run.md). Two things do not cross: there is no ObjC runtime
to hang the per-image metadata on, and there is no animated path, so a GIF decodes to its
first frame.

Guards in the fork are `#if os(Android)` / `#if !os(Android)`, never `canImport(...)`,
for the same poisoning reason — Kingfisher's non-Android platforms are all Apple, so the
platform gate is both safe and correct there.

The port also needs a public `DownloadTask` initializer, and no longer carries one:
`ImageDownloader.downloadImage` is `open`, but every `DownloadTask` initializer was
internal, so an override outside the module had nothing valid to return.
`init(cancelling:)` went upstream as
[#2576](https://github.com/onevcat/Kingfisher/pull/2576), merged 2026-09-13, together
with `isTaskCancelled` matching `.asyncTaskContextCancelled` — the reason
`FAOkHttpDownloader` reports. So did a way for that transport to feed progress:
progress reached the placeholder only through `DataReceivingSideEffect.onDataReceived`,
which takes a `SessionDataTask` and is internal.
`KingfisherParsedOptionsInfo.reportDownloadProgress(receivedSize:totalSize:)` went
upstream as [#2579](https://github.com/onevcat/Kingfisher/pull/2579), merged 2026-09-22.

Five things the port needed beyond the guards:

- **`@Observable` instead of `ObservableObject`.** `KFImage.ImageBinder` was Combine's;
  on Android it is `@Observable` and `KFImageRenderer` holds it in a `@State`. And
  `withAnimation` marks the *whole* Compose frame on SkipUI, so the binder records the
  load animation and the renderer applies it with `.animation(_:value:)` instead.
- **No `canImport` gate on the SwiftUI files.** skipstone's bridge generator silently
  drops a file whose top-level `#if` it cannot evaluate, and
  `#if canImport(SwiftUI) && canImport(Combine)` is one such. `KFImageRenderer` therefore
  got no Kotlin glue for its `@State`, `KFImage` was never made a `SkipUI.View`, and the
  result was a view that downloaded its image and drew nothing at all — no error
  anywhere. `KFImage` also has to name `View` in its conformance list rather than inherit
  it through `KFImageProtocol`, which the generator does not follow. The symptom to
  recognise: an empty `<Type>_Bridge.swift` under
  `.build/plugins/outputs/…/SkipBridgeGenerated/`.
- **The rendered image comes out of an `ImageHolder`, not out of the view value.** A
  SwiftUI `Image` is a value, so its bitmap reaches the screen only through a
  recomposition — and `KFImageRenderer` starts its load from the placeholder's `onAppear`,
  which SkipUI compiles to a Compose `SideEffect`, run *after* that composition has been
  applied. An image the memory cache already held therefore missed its own first frame.
  iOS has no such gap: SwiftUI delivers `onAppear` in time and
  `CallbackQueueMain.currentOrAsync` completes a memory hit synchronously. The answer is
  to read the bitmap in the draw phase instead — see
  [skip-ui § A draw-phase image](#a-draw-phase-image) for the primitive and the reasoning.
  `ImageBinder` owns a holder and mirrors every loaded image into it through
  `setLoadedImage(_:)`, not a `didSet`: the class is `@Observable` on Android and that
  macro rewrites stored properties.

  The image's opacity and zero-frame gates go with it, and that is half the fix — both are
  composition-phase reads, so gating on them is what put the bitmap a frame late. The
  holder needs no gate, drawing nothing until it is set, and because the image node is
  already painted underneath, releasing the placeholder cannot expose a frame with neither.
  The gate survives only for the passes a load transition owns, which `binder.animating`
  marks and a memory hit never enters.

  This replaced two earlier workarounds: a memory-cache read performed during composition,
  and a `placeholderWasShown`/`imageHadItsOwnPass` pair that held the placeholder one pass
  past the hand-off. Both worked; both were the wrong layer, and neither reached the
  avatars — which blank at every `RemoteView` state swap, since it renders `.loading` and
  `.loaded` in two branches of one `switch`, so the page arriving rebuilds the subtree and
  every `KFImage` in it gets a **fresh binder**.
- **A cache hit is delivered in the frame it is asked for**, which the holder alone did not
  buy. The holder is read in the draw phase, so it only helps an image whose bitmap lands
  before that frame's traversal — and a memory hit did not. The app sets
  `preferCacheOriginalData` (Skip's `UIImage` carries no animated-image metadata, so
  `DefaultCacheSerializer` cannot re-encode a GIF), which makes
  `originalDataUsed` true, and `KingfisherManager.deliverTargetCacheHit` then re-runs the
  processor on the *cached* image over the processing queue and returns through the callback
  queue. That round trip is always a frame: the return hop is a `Handler` post and the frame
  that posted it is itself one. So the holder was written after the frame that drew it, and
  the fresh binders above made that a guaranteed blank frame on every `RemoteView` swap.

  On Android the round trip buys nothing —
  `DefaultImageProcessor.process(item: .image(_:))` returns its input unchanged there,
  having no `kf.scaled(to:)` counterpart — so with the default processor the reprocessing
  is skipped and the image is handed over inline. A real processor still runs off the main
  thread, and the Apple branch keeps the hop it needs. Measured against Choreographer frame
  markers, opening a submission with a warm memory cache: the transition frame went from
  3 image nodes drawn with an empty holder to 0, **5 blank frames over 5 runs → 0 over 5**,
  and the transition now finishes a frame sooner.

- **A progress write Observation can see.** On Android `ImageBinder.updateProgress`
  assigns a new `Progress` instead of mutating the current one: under Observation only a
  write to the stored property is seen, so the placeholder fed by upstream's
  `reportDownloadProgress` never recomposed.

`Sources/Documentation.docc` is deleted in the fork rather than excluded: skipstone walks
the whole target directory and generates a bridge for every SwiftUI `View` it finds,
including the tutorial snippets, whose repeated `ContentView` steps then collide as
Kotlin redeclarations. `#if` around them does not help, for the reason above.

Adopting the fork moves iOS from upstream 8.10.0 to a branch based on upstream `master`
past 8.12.0 (`2fd07d84`, which includes #2579), merged into `android` as `c2cacbaa` on 2026-09-22.

## The other fork patches

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

    The rebuild also has to **put the link back on the placeholder**. `append(text:start:end:)`
    clips every annotation to the range it copies and the placeholder character is
    deliberately outside those ranges — `appendInlineContent` appends it separately, bare.
    So the parse's `LinkAnnotation` survived on everything around an image and on nothing
    at it. FA writes a mention as *one* anchor holding the avatar and the name
    (`<a class="iconusername"><img …> <span>name</span></a>`), which left the avatar dead
    while the name beside it was tappable. `splicingInlineContent` now re-pushes whatever
    `getLinkAnnotations` reports over the placeholder around the `appendInlineContent` call
    — the very `LinkAnnotation` objects `fromHtml` made, so they still carry the
    `LinkInteractionListener` feeding `onLinkTap`. `TextLinkScope` lays its clickable box
    over the link range's layout bounds, a placeholder has real bounds, and the inline
    `KFImage` installs no pointer-input node, so the tap reaches the box. A bare `<img>` (a smilie)
    is in no anchor, `getLinkAnnotations` comes back empty, and nothing is pushed.

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
- **SF Symbol mappings** for the symbols this app uses. Unmapped names render as a
  warning triangle. Six are now the mapping sent as skip-ui #525, picked by the symbol's
  *shape* rather than by what the app means by it: `bubble` → ChatBubbleOutline,
  `message` → Chat, `safari` → Explore (was Public), `exclamationmark.bubble` → Feedback
  (was CommentsDisabled), `ellipsis.bubble` → Sms (was Forum), `square.and.arrow.down` →
  SaveAlt (was FileDownload). `text.badge.star` → Info stays fork-only: Material has
  nothing shaped like it.
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
