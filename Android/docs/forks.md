# Forks

| Fork | Why |
|---|---|
| `Ceylo/Defaults` | Android port; `Defaults.defaultSuite` (see [Defaults](shared-sources.md#defaults)) |
| `Ceylo/skip-ui` | `listRowInsets` (and innermost-wins `listRow*` precedence); resuming an in-flight animation across composition disposal; a `ScrollView` that fills its scrolled axis; `Text(bridgedHTML:…)`; `Text(bridgedRichText:bridgedInlineViews:)`; `Text(bridgedSegments:…)`; `FlowRow`; a `GeometryReader` composed on the measure pass that still answers intrinsic queries; a draw-phase `ImageHolder`; springs that are springs; `.id` state reset scoped positionally rather than by swapping the state saver; geometry that reports a view's laid-out frame rather than its clipped one; SF Symbol mappings; `.glass`/`.glassProminent` drawn as bordered and `buttonBorderShape`; `glassEffect` drawn as the M3 floating surface; tab re-tap popping to root, then scrolling to top; a `List` under the status bar when the navigation bar is hidden; a `List` that restores its scroll position by the first visible keyed row and its offset; a plain `List`'s section header pinned below the status bar; no `List` row for an `EmptyView`; a `NavigationLink` in a `List` row drawn untinted; a tab badge's count in `onError`; `Color.material(bridgedRole:)`; a bridged `.task(id:)` that is really cancelled; `.updatesFrequently` as a polite live region; a sheet that calls its content only while presented and keeps the last one while it animates away; a `ScrollViewReader` proxy that resolves its scroll action when used; a stack insertion that keeps its enter transition when the stack recomposes before it has played; a principal toolbar item in the title's place, and a flexible toolbar spacer that only separates top-bar groups; a `Picker` listed inline in a `Menu`; a filled image cropped by its frame's alignment; a primary action kept at the toolbar's trailing edge; menu dividers drawn only between items; iOS-parity text layout (HTML line height, `.subheadline` weight, menu text/icon size, menu divider); [local notifications posted as iOS posts them](#local-notifications), communication ones as conversations |
| `Ceylo/skip-fuse-ui` | the Fuse side of each: `listRowInsets`, `Text(html:…)`, `Text(AttributedString)` / `Text(_:inlineViews:)` (disfavoured, so literals still localize), `Text.+`, `FlowRow`, `Image(holder:)`, `ButtonBorderShape`, `sheet`/`fullScreenCover` content passed as a builder, a `JavaBackedView` holding a global JNI reference, `glassEffect` bridged to SkipUI's surface, `GlassEffectContainer` bridged as a `Group`, an `AccessibilityTraits()` that doesn't recurse (upstream #132), `Color.material(_:)` for Material color roles SwiftUI has none for, plus `glassEffectUnion`/`glassEffectID`/`AnyTransition.animation`/`.glass`/`.glassProminent` un-`unavailable`d and `controlSize`/`contentShape` as pass-throughs; `#Preview` / `@Previewable` stubs (skiptools/skip#439) and `@Entry`; notification attachment options, categories and actions, `interruptionLevel` and `soundSetting`; the Intents types of a communication notification |
| `Ceylo/Kingfisher` | Android port: platform guards, a decode seam onto SkipSwiftUI's `UIImage`, a bridgeable SwiftUI layer, a rendered image that comes out of an `ImageHolder` rather than out of the view value, and `KFAnimatedImage` |
| `Ceylo/skip-foundation` | Android `UserDefaults` storing arrays and dictionaries; `JSONSerialization` keeping characters outside the BMP ([below](#why-skip-foundation-is-forked)) |
| `Ceylo/skip-web` | dependency identity only: it must name `Ceylo/skip-ui` and `Ceylo/skip-fuse-ui`, no source changes |
| `Ceylo/skip-bridge`, `Ceylo/skip-model`, `Ceylo/skip-android-bridge`, `Ceylo/skip-fuse` | dependency identity only, like skip-web: each names the forks above it, so the graph has one `skip-foundation` |

Which commit is which patch, and where each stands upstream, is the inventory in
[upstreaming.md](upstreaming.md), along with the gates each project sets for a PR.

All are on an `android` branch, referenced by URL + branch from `Package.swift` (and, for
Defaults and Kingfisher, the Xcode project too). While iterating, re-point the root
`Package.swift` at a local clone:

```
.package(path: "../../SkipForks/Defaults")     // instead of the URL + branch
```

The clone's directory must carry the repo's name: SwiftPM takes the package identity
from the last path component. A relative path out of the worktree makes Gradle builds
skip the [build slot](build-and-run.md#build-slots); an absolute one, like
`SKIPLOCAL`'s, keeps it. Push to the `android` branch before the step's gate.

The root `Package.resolved` **is** committed (a `!/Package.resolved` negation in
`.gitignore`), as is the Xcode workspace's copy; only `FAKit/Package.resolved` stays
ignored. Ten dependencies resolve from mutable `branch: "android"` refs, so without
the recorded revisions a release isn't reproducible. Refreshing a fork is `swift package
update <dep>`, then committing the diff. The root manifest declares swift-syntax, unused,
only so that update keeps the pin skip-fuse-ui's Android-only macros need; building it
from source costs ~45 s on a clean Android build.

**`android` is never rebased or force-pushed**: the committed revisions must stay
reachable. To pick up upstream, including a fork patch that has since merged there,
fast-forward the fork's default branch to upstream's, then merge it into `android`,
resolving the merged patch in upstream's favour.

**Do not run `skip android build` / `skip android test` inside a fork checkout.** A
framework package has no `.xcodeproj`, so both build modes share one `.build/`, and the
bridge pass strips the transpiled Kotlin of its dependencies without invalidating the
hashes llbuild tracks. The next `swift test --filter XCSkipTests` then fails with
thousands of `Unresolved reference 'sref'` that look like source errors. Recovery: `rm
-rf .build/plugins/outputs`.

## Why skip-ui / skip-fuse-ui are forked

Each patch, what it changes and why:

- **`listRowInsets`.** SkipUI hardcodes a 16 dp × 8 dp inset on every row, so rows
  cannot go full-bleed, and the row renders 32 dp narrower than the width the list
  reports, so `bestThumbnailUrl(for:)` picks a bucket no row asks for and every
  prefetch is wasted. The patch threads optional `EdgeInsets` through
  `ListItemModifier` and un-`unavailable`s `View.listRowInsets` in both repos.
- **Innermost `listRow*` wins.** SkipUI kept the first value walking outermost →
  innermost, the opposite of SwiftUI, which gave comment rows an ancestor's 5 dp
  vertical insets outside the view `CommentThreadConnector` draws in, so thread lines
  stopped short of each row's edge.
- **Resuming an animation across disposal** (`Animation.swift`). Scrolling a `List` row
  out of the composed window disposes it, and `rememberSaveable` slots come back already
  at their target while the `Animatable` (plain `remember`) is recreated there, so a
  half-played animation came back as its end state. The patch keeps a saveable record of
  the animation, its start, target and start time, and resumes the spec with a
  `StartOffset`. The deep-linked comment's highlight pulse needed it.
- **`ScrollView` fills its scrolled axis.** `.refreshable` is a nested-scroll
  connection, so the pull only worked over the content's own bounds: on the empty
  feed, over the text and nowhere else. The patch fills the scrolled axis before
  `verticalScroll`, as `RenderList` already does.
- **`@_disfavoredOverload` on `Text(AttributedString)`**, our own addition, a caution
  for every `Text` overload: `AttributedString` is `ExpressibleByStringLiteral`, so a
  bare `Text("…")` preferred it over `LocalizedStringKey`, and implicit markdown and
  localization stopped working app-wide. The fingerprint: only *bare* literals break.
  Any new `Text` initializer taking a literal-expressible parameter needs the attribute.
- **`GeometryReader` composes on the measure pass.** It used to render content only
  after a placement callback's recomposition, so every reader drew nothing on its first
  frame (`SubmissionMainImage` waited 616–689 ms). It now composes in a
  `BoxWithConstraints`; where an axis is unbounded the old wait stands. That
  `SubcomposeLayout` crashed on intrinsic queries, which SkipUI does make, so the box
  fills a `GeometryReaderLayout` answering every intrinsic with 10 dp, as SwiftUI's
  reader reports 10×10 pt.
- <a name="a-draw-phase-image"></a>**A draw-phase image.** `ImageHolder` is a bridged
  reference over a `MutableState<Bitmap?>`, which `Image(bridgedHolder:)` reads in
  `onDraw`; skip-fuse-ui vends it as `Image(holder:)`. Writing to it repaints without
  recomposing, so an image resolved before a frame's traversal is painted in *that*
  frame, and the node never has to be swapped in for a placeholder. Moving `onAppear`
  into composition would also land in the frame, but runs caller side effects in a pass
  Compose may replay. Verified against `Choreographer.postFrameCallback` markers, since
  `screenrecord` drops single frames. Kingfisher is the caller (see
  [below](#why-kingfisher-is-forked)).
- **Springs that are springs** (`Spring.swift`). Every spring was a ~500 ms tween eased
  with `EaseInOutBack`, which first moves *away* from its target; the progress bar,
  retargeted every ~100 ms, had a negative width in 290 of 822 frames and looked
  undrawn. Each initializer now builds a `SpringSpec` with SwiftUI's own mapping, and
  `delay(_:)` wraps it in a `DelayedAnimationSpec`.
- **`.id` resets state positionally** (`AdditionalViewModifiers.swift`). `TagModifier`
  handed a `.id` subtree a fresh `ComposeStateSaver` whenever the id changed, stranding
  every `Key` a descendant had saved, and a bridged `@State` then force-unwrapped nil:
  an abort at `StateSupport_Bridge.swift:11`. Kingfisher hit it, since `KFImage`'s `.id`
  is its URL, which follows the measured size across thumbnail buckets. The `key()`
  already in `TagModifier` resets saved state too, so the patch drops the swap and keys
  on an id *generation* as well.
- <a name="a-tenth-patch-laid-out-frames"></a>**Laid-out frames.**
  `onGloballyPositionedInRoot` read `boundsInRoot()`, which clips to every ancestor, so
  a partly visible row reported a shrunken size and a `minY` pinned at 0. SwiftUI reports
  the laid-out frame (a row's `minY` goes to −1368 pt), so the patch uses `size` +
  `positionInRoot()`. Rows reporting more than one size in a fling: 47 of 48 → 0, and
  `.id` changes over 120 fling cycles: 1671 → 0. `trackFirstItemTop` and
  `followItem` now see a negative `minY`, as on iOS, and kept their behaviour.

The `.id` crash first came from a tester's Galaxy S25 (360 dp wide), not the 411 dp
emulator, because at 411 dp every row picks the same thumbnail bucket whatever its
clipped height. `wm density 480` on the emulator reproduces it, 3/3 in the first scroll
cycle, and is the regression test for both patches above. Not fixed, and not fixable
from the fork: after process death a restored `Key` misses its in-memory map the same
way; it wants a null check in skipstone's generated `syncState`. The app dodges it,
since a killed process cold-starts through autologin.

### After upstream #500 <a name="after-upstream-500"></a>

Upstream #500 rewrote `GeometryReader` around a `GeometryReaderState` whose proxy
observes per property. It fixed the clipped *size* its own way but kept `boundsInRoot()`
for the frame (its `globalFrameReaderObservesMovementAndClipping` asserts the clip) and
went back to waiting for placement. The merge keeps #500's state and proxy, feeds it the
laid-out frame, and keeps the measure-pass `BoxWithConstraints`;
`actualReaderReportsUnclippedGlobalFrame` pins the frame.

The same merge brought one regression: #500 rendered a `.resizable()` asset image with no
intrinsic size yet through a filling `RenderPainter`, and the layout outlived the load, so
`HomeView`'s app icon took its `VStack`'s whole height. Upstream #543 fixed it (no fill
when the image has a content mode), and the fork uses that fix since its 2026-10-19 merge.

That merge also put the measure-pass reader's bounded constraints into the proxy's
`sizePx`, which upstream `ed7437a` split out of the global frame.

## One location per identity

SwiftPM allows a package identity one location across the whole graph, and
`Ceylo/skip-fuse-ui` forces the question: it calls `SkipUI.Text(bridgedHTML:)` outside
`#if SKIP`, so it does not compile against upstream skip-ui, on Apple either. **Every**
manifest in the graph therefore names `github.com/Ceylo/skip-ui`: the two skip forks and
Kingfisher say so themselves, which is the whole reason `Ceylo/skip-web` exists.

The app manifests must **not** re-declare skip-ui: SwiftPM reports that as "dependency
'skip-ui' is not used by any target", and a chain still pointing upstream as
"conflicting identity for skip-ui". Both are warnings it says will become errors. A
third declaration once flipped SwiftPM's tie-break and left a pin with the fork's
revision at upstream's location, which could not be checked out. Recovery, should a
stale pin bring that back: drop the offending pins from the workspace `Package.resolved`,
`rm -rf` that checkout and `artifacts/skip`, and resolve again.

**A branch pin is refreshed, not re-resolved**: `xcodebuild
-resolvePackageDependencies` re-records the revision already pinned. On the Xcode side
even deleting the pin is not enough: SwiftPM trusts `workspace-state.json`'s
`checkoutState` over the branch, and keeps printing `@ android (<old sha>)` with exit 0.
All three have to go together:

```
DD=$(xcodebuild -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILD_DIR =/{print $2}' | sed 's|/Build/Products||')
# 1. the pin, from FurAffinity.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# 2. the dependency's entry in "$DD/SourcePackages/workspace-state.json"
rm -rf "$DD/SourcePackages/checkouts/<Dep>"          # 3. the checkout
xcodebuild -project FurAffinity.xcodeproj -scheme FurAffinity -resolvePackageDependencies
```

## Why Kingfisher is forked

Android had reimplemented, in Swift and Kotlin, what iOS gets from Kingfisher: a decoded
LRU, coalescing, off-main decoding, disk staging with its own expiry, and a KFImage-shaped
view. The coupling to ImageIO that made a port look impossible is narrow: every decode
funnels through five entry points in `Sources/Image/Image.swift`, and SkipSwiftUI's
Bitmap-backed `UIImage` answers all of them. A shim of `ImageIO` or `CoreGraphics` would
re-run [module-name poisoning](build-and-run.md#module-name-poisoning), and
`UIImage(cgImage:)` is unavailable anyway. What does not cross: per-image metadata (no
ObjC runtime), except a GIF's bytes, which a `UIImage` subclass carries for
`KFAnimatedImage` (see [images.md § Animated images](images.md#animated-images)). Guards are `#if
os(Android)`, never `canImport`, for the same poisoning reason.

The public `DownloadTask` initializer a custom downloader needs, and a way for it to feed
progress (`reportDownloadProgress`), both went upstream (#2576, #2579). Beyond the
guards, the port needed:

- **`@Observable` instead of `ObservableObject`** for `KFImage.ImageBinder`, held in a
  `@State` by `KFImageRenderer`, and the load animation applied with
  `.animation(_:value:)`, since `withAnimation` marks the whole frame on SkipUI.
- **No `canImport` gate on the SwiftUI files.** skipstone silently drops a file whose
  top-level `#if` it cannot evaluate, and `canImport(SwiftUI) && canImport(Combine)` is
  one, which gave a `KFImage` that downloaded and drew nothing. `KFImage` must also name
  `View` in its own conformance list. The symptom: an empty `<Type>_Bridge.swift` (see
  [Checking a generated bridge](shared-sources.md#checking-a-generated-bridge)).
- **The rendered image comes out of an `ImageHolder`**, not out of the view value.
  `KFImageRenderer` starts its load from the placeholder's `onAppear`, a Compose
  `SideEffect` run after composition, so even a memory hit missed its first frame.
  `ImageBinder` mirrors every loaded image into a [draw-phase
  holder](#a-draw-phase-image) through `setLoadedImage(_:)` (the `@Observable` macro
  rewrites stored properties, so no `didSet`), and the opacity and zero-frame gates,
  composition-phase reads themselves, go except during a load transition.
- **A cache hit is delivered in the frame it is asked for.** With
  `preferCacheOriginalData` (so a Bitmap is never re-encoded for the disk cache),
  `deliverTargetCacheHit` re-runs the processor through two queue hops, which always
  cost a frame. On Android the default processor returns its input unchanged, so with it
  that round trip is skipped. Opening a submission on a warm cache: 5 blank frames in 5
  runs → 0.
- **A progress write Observation can see**: `updateProgress` assigns a new `Progress`
  rather than mutating it.

`Sources/Documentation.docc` is deleted in the fork rather than excluded: skipstone
generates a bridge for every SwiftUI `View` it finds, and the tutorial's repeated
`ContentView` steps collide as Kotlin redeclarations.

## The feed-gaps patches

What sharing `SubmissionsTabView` needed ([screens.md § Followed
feed](screens.md#followed-feed)).

skip-ui:

- **`glassEffect` draws the M3 floating surface**: `surfaceContainer` in the given shape
  under a 3 dp shadow that doesn't clip, what M3 draws under a floating toolbar or FAB.
  `glassEffectUnion` / `glassEffectID` are pass-throughs.
- **Re-tapping the selected tab** pops to the root, then scrolls to top. `TabView` bumps
  a per-tab `_tabReselectSignal`; the tab's `NavigationStack` calls the new
  `Navigator.navigateToRoot()` or runs the root's scroll-to-top action. Entry content
  and sheets clear the signal, so nested stacks don't react.
- **A `List` under the status bar with the bar hidden.** `NavigationStack` clamped the
  content's top inset to the status bar even with no top bar. Two `List` follow-ons:
  `scrollTo(id)` stops below the safe-area header, as iOS stops below the content inset,
  and a list resting at its top is scrolled back to the header that arrives one pass late.
- **A `List` restores its scroll position by row key.** `rememberLazyListState` saves
  only an index, so a list composed again after the rows above it changed lands on
  another row — as after every push or tab switch, through the late header. `RenderList`
  also saves the first visible row's key and re-applies it in the first measure pass.
- **A bridged `.task(id:)` is cancelled** when its id changes or the view leaves.
  SkipLib's `Task.cancel()` never cancelled the coroutine the bridge waited on.
  **This changes behaviour app-wide**: every `.task` on Android is now cancelled on
  disappear, as on iOS. Found through the Undo snackbar, whose undone batch's timer
  committed the next batch.
- **`.updatesFrequently` is a polite live region**, which is what Material's snackbar
  sets; SkipUI declared the trait and dropped it.
- **A shadow's copy of its content is out of the accessibility tree** — upstream since
  #538; TalkBack had read the snackbar as "Submission deleted. Submission deleted.
  Unlabelled. Undo".

skip-fuse-ui:

- **`glassEffect` bridges to SkipUI** with its shape, instead of returning `self`.
- **`GlassEffectContainer` bridges as a `Group`.** A View with only a `body` is not
  `SkipUIBridging`, so every glass control wrapped in one drew nothing.
- **`AccessibilityTraits()` no longer recurses** (cherry-picked from upstream PR #132):
  `init() { self = [] }` overflowed the stack on any array literal.

## The other fork patches

- **`Text(html:)`** hands markup to Compose's own `AnnotatedString.fromHtml`, which is
  how FA's rich text renders. Its decisive advantage: it applies
  **`ParagraphStyle(textAlign)`**, so a `[center]` block and the text around it live in
  one `Text`, which styled runs cannot express. It handles weight, emphasis, colour,
  headings, lists and links unaided. What it misses:
  - `<code>`, and alignment except `style="text-align:start|center|end"` on a block.
    FA compiles `[center]` to a class on `<code>`, so `FAHTMLNormalizer` rewrites it;
    that pass absorbs FA's other quirks too, and is tested on iOS against the parser
    fixtures.
  - `<hr>`, dropped without a line break: the normaliser hoists each rule to the root,
    and `HTMLView` draws a `Divider()` between the pieces.
  - `<img>`, dropped but **leaving a U+FFFC**, where `RichText.splicingInlineContent`
    splices inline content, iterating UTF-16 units as Compose counts offsets. It also
    re-pushes the `LinkAnnotation` over the placeholder: FA writes a mention as one
    anchor around the avatar and the name, and the avatar was dead.

  A tapped link goes to `onLinkTap` through a `LinkInteractionListener`, never to
  Compose's `UriHandler`, which would open the browser first. Parsing is `remember`ed on
  the markup and the link colour.
- **`Text.+`** is unavailable upstream. Each `Text` modifier now also records into a
  `TextRunStyle`, additively, so a concatenation becomes one `AnnotatedString` with a
  `SpanStyle` per segment. Colours are read through a `RichTextColorStyle` protocol
  rather than casts. Anything that cannot cross as a `SpanStyle` (`tracking`,
  `font(.custom)`, a gradient `foregroundStyle`, …) is a `preconditionFailure` naming the
  modifier: silent dropping is this port's recurring failure mode.
- **`Text(AttributedString)`** is unavailable upstream. Runs cross as records, one per
  run (RS-separated, fields US-separated), into
  `SkipUI.Text(bridgedRichText:bridgedInlineViews:)`, bypassing `LocalizedStringKey`
  since the content is user data. The encoder reads `\.font`, `\.foregroundColor`,
  `\.underlineStyle`, `\.strikethroughStyle` and `\.baselineOffset`, declared by
  SkipSwiftUI **only where SwiftUI's own is absent** (on Darwin it makes the scope
  ambiguous). Colours cross as decimal ARGB or a `primary`/`secondary`/`accent` token,
  since SkipLib's `Int64(_:)` takes no radix. Separators are spelled with four hex
  digits (`\u{001E}`), because the transpiler turns `\u{1E}` into an invalid Kotlin
  escape.
  - **`Text(_:inlineViews:)`** splices views at the object-replacement characters.
    `TextInlineView` carries an explicit size, since Compose reserves the space before
    composing the view. Use `PlaceholderVerticalAlign.Center`, not `TextCenter`, and drop
    the style's fixed `lineHeight`, or a 50 pt avatar spills onto the next line.
- **`FlowRow`** replaces SwiftUI's `Layout`, which can't be emulated: an opaque `Content`
  gives a Fuse module no access to its subviews. `Helper Views/Android/FlowLayout+Android.swift`
  keeps the iOS call signature.
- **`AnyTransition.animation`**, **`glassEffectUnion`** and **`glassEffectID`** are
  pass-throughs rather than unavailable: `#available(iOS 26, *)` is true off-Apple, so
  shared code takes its Liquid Glass branch on Android.
- **SF Symbol mappings** for the symbols this app uses; unmapped names render as a
  warning triangle. Most are upstream (skip-ui #525, mapped by the symbol's shape);
  `text.badge.star` → Info stays fork-only, and the tab icons `rectangle.grid.2x2` →
  GridView and `slider.horizontal.3` → Tune came later, as did the Notes tab's (`tray`,
  `archivebox`, `square.and.pencil`, `message.badge.fill`, and the filter, whose plain and
  `.fill` forms map to FilterList's outlined and filled icons, one and the same glyph:
  Material has no circled filter), and `folder` → Folder for the gallery's folders menu.
- **A top bar's principal item and spacers.** A `.principal` item was appended to the
  leading items, so the navigation title still drew beside it; it now takes the title
  slot. A flexible `ToolbarSpacer` took a flexible width in the top bar's actions row,
  which then spanned the whole bar and squeezed the items after it; in a top bar it is
  now the fixed gap, all it does in SwiftUI's navigation bar. Both are covered by
  `ToolbarItemsTests`.
- **A `Picker` inside a `Menu`** drew its own collapsed dropdown, which did nothing when
  tapped. Its options are now the menu's items, the selection checked, and an option that
  is itself a `Button` contributes only its label, as in SwiftUI.
- **Text layout parity with iOS**, each measured off screenshots:
  - Material's typography **fixes a line height** (`bodyLarge` 24sp on a 16sp face),
    where SwiftUI uses font metrics, so HTML ran 24 dp per line against iOS's ~17.9 pt.
    The HTML branch clears `lineHeight` (18.7 dp); `richText`, `segments` and markdown
    keep M3's.
  - **`.subheadline` maps to `bodyMedium`**, not `titleSmall` (Medium 500): same metrics,
    regular weight, as iOS's subheadline is.
  - **Menu items use `bodyLarge`**, set in `RenderDropdownMenuItems`, where Material
    supplies `labelLarge`; icons follow (14 → 16 dp). The setter is spelled
    `$0.setfont(…)`, because skipstone emits a Swift `var` with a custom getter as a
    Kotlin `val` plus `setX`.
  - **A menu `Divider` is drawn with `outlineVariant`**: `Color.separator` resolves to
    exactly a `DropdownMenu`'s elevation-3 background.

  Left as Material intends: the type-scale sizes, letter tracking, the 48 dp menu row,
  and trailing menu-icon placement.
- **A filled image is cropped by its frame's alignment** (`e844ccd`, `0e97371`,
  `cca6f8a`). `ImageLayout` centred its own overflow, so the user page's banner (`.fill`,
  then `.frame(…, alignment: .leading).clipped()`) showed its middle where iOS shows its
  left. Frames now pass their alignment down as `_frameAlignment`, each only on the axes
  it sizes; overlays and backgrounds pass their own. Passing the overflowing size up
  instead doesn't survive `KFImage`'s id'd `ZStack`, which renders through
  `AnimatedContent` and clamps it.
- **A primary action stays at the toolbar's trailing edge** (`bb96c29`), as on iOS.
- **A menu divider is drawn only between two items** (`69b4cb8`), as on iOS: a leading,
  trailing or repeated `Divider`, a `Section`'s included, draws nothing. The ⋮ menu ended
  with one, and the gallery's folders menu started with one.

## Local notifications

Upstream already posts without a delegate (#555, cherry-picked ahead of a full sync,
since #583's `List` rewrite conflicts with the fork's) and delivers taps to
`didReceive` (#566). What the background refresh still needed, in `dc39400` and
skip-fuse-ui `5b608cd`:

- **No activity required.** Settings, `add` and removals took
  `UIApplication.shared.androidActivity`, so a background job's process posted nothing and
  read `.notDetermined`. They use the application context; authorization is
  `areNotificationsEnabled()`.
- **Images where iOS draws them.** An image attachment became the small icon, which
  Android draws from its alpha alone: a white blob. A visible image is now the large
  icon, and only a `ThumbnailHiddenKey` one the expanded `BigPictureStyle` picture (so an
  avatar isn't blown up to full width), and
  `UNNotificationAttachment(identifier:url:options:)` infers the image type from the
  extension, as iOS does.
- **Due requests post before `add` returns**, stamped `setWhen`. Each went through
  its own WorkManager job, which runs in no particular order, so the newest item
  wasn't reliably on top; and the attachment files were read after the caller had
  moved on.
- **A tap keeps the running activity**: the intent adds `SINGLE_TOP` to
  `CLEAR_TOP`, which alone recreates it and loses the root view's `@State`. #566's
  new-intent listener then hands the tap to `didReceive`.
- **`soundSetting` is `.enabled`** rather than unavailable: the channel decides.
- **Categories and actions** (`f496755` + `5e023c8` + `a616f6e`, skip-fuse-ui `1f0574a` + `6d8d80b` + `18ad2d9`). `UNNotificationCategory`,
  `UNNotificationAction` and their options, saved by `setNotificationCategories` as iOS
  keeps them. A request's category gives the notification a button per action: a
  `.foreground` one opens the app as a tap does, any other reaches
  `NotificationActionReceiver`, declared in SkipUI's own manifest, which hands the
  response to `didReceive` without opening the app. Taps and buttons build the response
  from the notification's data, so it carries the request's content: title, body,
  category, `userInfo` and attachments. `.authenticationRequired` asks for an unlock
  (Android 12+), `.customDismissAction` reports a swipe-away, and a chosen action removes
  its notification unless the delegate posted it again. `interruptionLevel = .passive`
  posts silently, and replacing a notification still showing keeps its place.
  `.destructive` and the other category options have no Android effect. An Android-only reveal key came first
  (`9edd402` to `cca0169`); it was replaced by this real API, as the forks carry no
  API Apple's SDK lacks.
- **Attachments outlive their files** for a request posted later: `add` copies them into
  a store of its own, as iOS moves them. A later `add` prunes, at most every 10 minutes,
  the copies of notifications neither showing nor queued for a day.
- **Communication notifications as conversations** (`aa6ac8c` + `d4a7788` + `c491a7e`, skip-fuse-ui `cbf4494` + `d2fbd5d`).
  `INPerson`, `INImage`, `INSendMessageIntent` and `INInteraction` as Apple declares them,
  plus `UNNotificationContent.updating(from:)` and `mutableCopy()`. A donated message
  intent is a long-lived shortcut, and content updated from it a `MessagingStyle`
  conversation on that shortcut. SystemUI reads its image through
  `NotificationAttachmentProvider`, a read-only provider of the attachment store, because
  a Skip library can't ship the `res/xml` paths file a `FileProvider` needs. Every post but
  an active replacement sets only-alert-once, which also keeps SystemUI from counting a
  passive update as an unread message.

## Why skip-foundation is forked

The notification queue (`Defaults[.pendingNotificationQueue]`, an array of JSON strings)
never persisted on Android, and the flush read back an empty queue. Two bugs, both
covered by Robolectric tests that fail without the patch:

- **`UserDefaults.set(_: Any?)` dropped arrays and dictionaries** (`// we ignore`), with no
  error, while reads in the same process returned nothing. They are now stored as JSON,
  marked with an unrepresentable-type id (5, 6) that `object(forKey:)` decodes.
- **`JSONSerialization` broke every emoji.** `JSONWriter` wrote each `Character`
  separately, and on Kotlin that is one UTF-16 unit, so each surrogate was UTF-8-encoded
  alone, as "?". The escaped string is now written in one piece.

The fork is cut from the tag the app had pinned (1.4.6), not from `main`. Its own `swift
test` resolves the newest Skip (1.9.16 when this was written), whose transpiler accepts
`Data(string.utf8)` and `String(data:encoding:)` inside `UserDefaults`, where the app's
pinned 1.9.12 does not: check a fork patch against the app's Skip, not only the fork's
tests. After changing a skip-foundation file, `Scripts/Android/clean.sh` before building
the app. Kotlin's incremental compile regenerates only that file and resolves it against
stale state ("Unresolved reference 'utf8Data'" for an extension the module still declares).

Identity costs four more forks. skip-foundation is named by skip-bridge, skip-model and
skip-android-bridge, and skip-android-bridge by skip-fuse, so each of those, and skip-ui,
skip-fuse-ui and skip-web, names the Ceylo URL. Like skip-web, the four new ones carry no
source change and retire with the skip-foundation patches.

