# Forks

| Fork | Why |
|---|---|
| `Ceylo/Defaults` | Android port; `Defaults.defaultSuite` (see [Defaults](shared-sources.md#defaults)) |
| `Ceylo/skip-ui` | `listRowInsets` (and innermost-wins `listRow*` precedence); resuming an in-flight animation across composition disposal; `Text(bridgedHTML:…)`; `Text(bridgedRichText:bridgedInlineViews:)`; `Text(bridgedSegments:…)`; `FlowRow`; SF Symbol mappings; iOS-parity text layout (HTML line height, `.subheadline` weight, menu text/icon size, menu divider) |
| `Ceylo/skip-fuse-ui` | the Fuse side of each: `listRowInsets`, `Text(html:…)`, `Text(AttributedString)` / `Text(_:inlineViews:)`, `Text.+`, `FlowRow`, plus `glassEffect`/`AnyTransition.animation` un-`unavailable`d |

All on an `android` branch, referenced by URL + branch from `Package.swift` (and,
for Defaults, the Xcode project too). While iterating, re-point the root
`Package.swift` at a local clone:

```
.package(path: "../../SkipForks/Defaults")     // instead of the URL + branch
```

then push to the `android` branch before the step's gate.

The root `Package.resolved` **is** committed (`.gitignore` carries a `!/Package.resolved`
negation; `FAKit/Package.resolved` and the Xcode workspace's copy stay ignored). Three
deps resolve from mutable `branch: "android"` refs, so without the recorded revisions a
release APK isn't reproducible. Refreshing a fork is still
`swift package update <dep>` — now followed by committing the resulting diff.

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

**Note:** skip-ui arrives transitively via skip-fuse-ui, so overriding it needs its own
entry in `Package.swift`'s `dependencies`, not just the fuse-ui one.

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
- **SF Symbol mappings** for the symbols this app uses (`safari`,
  `square.and.arrow.down`, `bubble`, `exclamationmark.bubble`, `ellipsis.bubble`,
  `message`, `text.badge.star`). Unmapped names render as a warning triangle.
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
