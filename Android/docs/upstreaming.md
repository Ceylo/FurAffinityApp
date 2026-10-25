# Upstreaming the forks

[forks.md](forks.md) records *what* each fork patch does and why. This records how one
travels back to its origin project, so the forks shrink instead of drifting.

Four dependencies are forked, plus a fifth that exists only to re-point two of the others.
Patches already sent are listed in [Opened PRs](#opened-prs); everything else below is the
process to follow when one is sent.

**The first rule: every pull request is opened as a draft** — `gh pr create --draft`, on
every one of these repositories, without exception. Marking one ready for review needs
Ceylo's explicit approval, each time. Nothing in this document authorises it, and a draft
is never described as submitted.

## Inventory

| Fork | Upstreamable | Stays in the fork |
|---|---|---|
| `Ceylo/skip-ui` | all of it | — |
| `Ceylo/skip-fuse-ui` | all but one commit | `cfa7d82` — names our forks in `Package.swift` |
| `Ceylo/Kingfisher` | the Android port, only if onevcat wants one | skipstone plugin, the unconditional `SkipFuseUI` edge, the `Documentation.docc` deletion, the dynamic-library manifest |
| `Ceylo/Defaults` | `Defaults.defaultSuite`, pitched on its own merits | dropping `DefaultsMacros` + swift-syntax, the `#if !os(Android)` guards |
| `Ceylo/skip-web` | nothing | `64de0f8` — dependency locations only; required today, retires when the two above land |
| `Ceylo/skip-foundation` | both patches | — |
| `Ceylo/skip-bridge`, `skip-model`, `skip-android-bridge`, `skip-fuse` | nothing | the `Package.swift` re-point to `Ceylo/skip-foundation`; retire with its patches |

Per patch. "Paired" means the change touches API surface and so needs a matching
`skip-fuse-ui` PR *and* a Showcase playground (see [Skip](#skip-ui--skip-fuse-ui) below).

| Patch | Goes to | Paired | Note |
|---|---|---|---|
| `22e8919` `listRowInsets` | skip-ui + `0d5d47a` | yes | un-`unavailable`s API in both repos |
| `5110e81` innermost `listRow*` wins | skip-ui | no | drafted as #549 (topic `fix/list-row-innermost-wins`), re-cut on `main` without `insets` (background and separator only), with Robolectric `testInnermostListRowBackgroundWins` and showcase #139 (a Row Modifiers page). iOS 26.5 confirmed innermost-wins for both. #532 edits the same lines; its new comment claims innermost-wins over unchanged outermost-wins code |
| `1b25638` `FlowRow` | skip-ui + `09a3e69` | yes | new container; `Layout` cannot be emulated, so argue the container |
| `23ac3bd` menu body text + visible divider | skip-ui | no | **split into two PRs** — the text/icon size and the `outlineVariant` divider are separate fixes |
| `ad375fb` `.subheadline` → `bodyMedium` | skip-ui | no | drafted as #551 (topic `fix/subheadline-body-token`) with `testSubheadlineIsRegularWeight`. Measured on the Text playground: ink per px of width 8.9 → 7.2 (`.body` 7.8, `.headline` 9.7). Side effect review found: `bodyMedium`'s letter spacing is 0.25sp vs 0.1sp, so text can rewrap |
| `eaa6abe` resume animation across disposal | skip-ui | no | the recycling-boundary fix; largest single non-text patch |
| `4b30753` `ScrollView` fills its scrolled axis | skip-ui | no | sent as #541 (topic `fix/scrollview-fills-scrolled-axis`), **vertical half only**: review dropped the `fillMaxWidth()` before `horizontalScroll`, which the vertical pull never needed and which only took horizontal drags from parent gestures. Adds a Robolectric pull-below-short-content test. Large title, measured: a drag on short content already collapsed it; the patch only extends where the drag can start. `ScrollView { LazyVStack }` has the same gap, unfixed — a likely follow-up |
| `f4776db` `glassEffect` / `AnyTransition.animation` pass-throughs | skip-fuse-ui | no | fuse-ui only; `glassEffect`'s half is superseded by `9b8671b` + `6c66c8d` |
| `ef2f9e3` `GlassEffectContainer` pass-through | skip-fuse-ui | no | send with `f4776db`: same argument, same file. Drew nothing until `e0600ec` bridged it as a `Group` — squash the two |
| `9b8671b` + `6c66c8d` `glassEffect` draws the M3 floating surface; `glassEffectUnion`/`glassEffectID` pass-throughs | skip-ui + skip-fuse-ui | yes | a design call (opaque `surfaceContainer` + 3 dp shadow, not a blur) — argue it from M3's floating toolbar/FAB |
| `f54f6e8` `rectangle.grid.2x2` / `slider.horizontal.3` mappings | skip-ui | no | drafted as #548 (topic `feature/sf-symbol-grid-tune`) with glyph comments 􀇷 / 􀌆; the rows were added to showcase #123 rather than a new PR |
| `3dcb579` Notes SF Symbol mappings | skip-ui | no | same shape as #525; both forms of the filter symbol map to `FilterList` |
| `4479648` principal toolbar item in the title slot; flexible top-bar spacer as a fixed gap | skip-ui | no | **two PRs**, one fix each; Robolectric `ToolbarItemsTests`, mutation-checked |
| `c8bff3d` `Picker` listed inline in a `Menu` | skip-ui | no | no Robolectric test yet: add one before sending |
| `001f4ec` tab re-tap pops to root, then scrolls to top | skip-ui | no | Material and iOS parity; adds internal `Navigator.navigateToRoot()` |
| `ca5fad0` `List` under the status bar with the nav bar hidden | skip-ui | no | bug fix plus its two `List` follow-ons (`scrollTo` offset, late header) |
| `91826c2` `List` restores its scroll position by row key | skip-ui | no | Robolectric `testListRestoresFirstVisibleRowByKey`, mutation-checked. Upstream, argue it from rows inserted above while away, since the late header is `ca5fad0`'s; `LazyVStack` and the grids keep the index-only restore |
| `1335ebf` bridged `.task(id:)` is really cancelled | skip-ui | no | sent as #540 (topic `fix/bridged-task-cancellation`, with `22ff079` squashed in). **Upstream differs from the fork**: review found `1335ebf` could run `onCancel` twice (handler and re-check both fire) from an unsynchronised captured var; the PR awaits a completion `Job` under `withTaskCancellationHandler`, registered after the action, and captures the effect's own `bridgedAction` instead of `rememberUpdatedState`. Take #540's version back into the fork. Regression from #420 |
| `88ac81d` `.updatesFrequently` → polite live region | skip-ui | no | sent as #539 (topic `fix/updates-frequently-live-region`). Not VoiceOver's meaning — Apple's trait lets the client *poll*, TalkBack reads every change (a 1 Hz `Text` queued 8 times in 8 s); the PR puts that trade-off first, and keeping the mapping is Ceylo's call. Pitfall, measured: a region that stays mounted while it **animates** out is read again (3–4×); without the animation it isn't, so apply it only while shown, as M3's `SnackbarHost` does. The trait doesn't reach a container's children |
| `d1905bc` `AccessibilityTraits()` recursion | skip-fuse-ui | no | already upstream as PR #132 (not ours), cherry-picked; drop it from the fork when #132 merges |
| `d9ad308` + `15a34f4` `#Preview` / `@Previewable` stubs | skip-fuse-ui | no | fixes skiptools/skip#439 (no maintainer reply since 2025-06). Squash the two; topic branch `feature/preview-macro` is cut from 1.18.2 and names upstream skip-ui. Expect pushback on the from-source swift-syntax build |
| `60671f0` → `1d56dc9` + `f0e4d6c` runs encoder | skip-ui + skip-fuse-ui | yes | **collides**, see below. `60671f0`/`79dc36f` are the superseded markdown cut — do not send them |
| `59f7693` + `de02184` inline content + its link | skip-ui + `737dcfa` | yes | **collides** |
| `193e97c` doc-comment correction on `Text(_:inlineViews:)` | skip-fuse-ui | no | squash into whichever inline-views PR goes; not a PR of its own |
| `bf0c6ad` + `28717f9` HTML via `fromHtml` | skip-ui + `30a2abd` | yes | **collides** with #436 on link handling |
| `cad81a8` `Text + Text` | skip-ui + `967a19a` | yes | **collides** head-on with #453/#118 |
| `9eb2c87` `@_disfavoredOverload` on `Text(AttributedString)` | skip-fuse-ui | no | belongs with whichever attributed-text PR lands; the trap is worth writing up either way |
| `5a21355` `GeometryReader` composes on the measure pass | skip-ui | no | fidelity fix (no blank first frame). Before sending, check whether it causes the intrinsic-measurement crash under a scroll: `BoxWithConstraints` is a `SubcomposeLayout` and the old `Box` was not. Now rebased onto #500's `GeometryReaderState` in fork merge `0a6d781` |
| `23154a0` `ImageHolder`, read in the draw phase | skip-ui + `c59b1a7` | yes | new API; its only caller today is the Kingfisher fork (`07f72deb`), so argue it from Coil's `AsyncImagePainter`, not from Kingfisher |
| `524153a` `.id` resets state positionally | skip-ui | no | no API change; fixes a regression in upstream `4ed8380`/#330. Swapping in a fresh `ComposeStateSaver` strands every `Key` a descendant already saved, and a bridged `@State` then force-unwraps the nil. Argue it as Compose correctness: positional scoping is the documented reset mechanism, and `rememberSaveable`'s own `key` parameter is deprecated precisely for bypassing it. Sent as #550 (draft) |
| `7ef63a0` geometry reports the laid-out frame, not the clipped one | skip-ui | no | no API change; SwiftUI parity in one helper (`onGloballyPositionedInRoot`). `boundsInRoot()` is `localBoundingBoxOf(this, clipBounds = true)` — an unexamined default since the first `GeometryReader`. Mention the one-argument alternative, `localBoundingBoxOf(this, clipBounds = false)`, and why not: it returns a bounding box, so a rotated node's size would differ, where `positionInRoot()` + `size` is SwiftUI's untransformed frame. Since #500 the *size* half is upstream's own; argue the frame against its `globalFrameReaderObservesMovementAndClipping`, which asserts the clip ([forks.md § After upstream #500](forks.md#after-upstream-500)) |
| `e844ccd` + `0e97371` + `cca6f8a` a filled image cropped by its frame's alignment | skip-ui | no | squash the three. Robolectric `testFilledImageOverflow*`, mutation-checked (leading/trailing fail without `e844ccd`; the one-axis-frame and overlay cases without `cca6f8a`). Adds the internal `_frameAlignment` environment value |
| `908239e` `folder` mapping | skip-ui | no | Robolectric `testFolderSymbolMapsToMaterialIcon`; same shape as #548 |
| `bb96c29` primary action trailing-most | skip-ui | no | Robolectric `ToolbarItemsTests.primaryActionStaysTrailingMost`, fails without the patch |
| `69b4cb8` menu dividers only between items | skip-ui | no | Robolectric `MenuDividerTests.onlyDividersBetweenItemsAreDrawn`, fails without the patch (100 px vs 97) |
| `dc39400` + `168d90d` + `5b608cd` local notifications as iOS posts them | skip-ui + skip-fuse-ui | yes | **split into four PRs**: application context, attachments as large icon / big picture (with the options init), immediate post with `setWhen`, `SINGLE_TOP`. Robolectric `NotificationRequestTests` covers the post and the icons. `fb1c589` is #555 cherry-picked; drop it at the next sync |
| `9edd402`…`a616f6e` + `bd03c7e`…`18ad2d9` notification categories and actions, `interruptionLevel`, attachment store | skip-ui + skip-fuse-ui | yes | squash: the reveal keys of `9edd402`–`cca0169` are gone. Two PRs: the attachment store (iOS semantics, needed by any delayed request), then categories/actions with `interruptionLevel`. Robolectric `testCategoryActionsBecomeButtons`, `testButtonHandsItsResponseToTheDelegate` (presses the real button), `testCategoriesAreSaved`, `testPassiveInterruptionLevelPostsSilently`, `testForegroundButtonIntentIsItsActionsResponse`, `testTapResponseCarriesTheRequestsContent`, `testCustomDismissActionReportsTheDismissal`, `testAttachmentCopyOutlivesTheOriginal` |
| `aa6ac8c` + `d4a7788` + `cbf4494` + `d2fbd5d` communication notifications as conversations | skip-ui + skip-fuse-ui | yes | squash. Apple's Intents types plus `updating(from:)`/`mutableCopy()`; after the categories PR, since it builds on the attachment store. No Robolectric test yet: it needs one posting a message intent and checking the `MessagingStyle` messages and the pushed shortcut |
| `844f754` + `36c9bef` + `96a940d` `UserDefaults` arrays and dictionaries | skip-foundation | no | squash the three. Robolectric `test_setValue_Array` / `test_setValue_Dictionary`. Cut from 1.4.6 |
| `6953840` `JSONSerialization` outside the BMP | skip-foundation | no | Robolectric `test_serializeStringOutsideTheBMP`; any Skip app's JSON loses its emoji today |
| `2b2dc459` + `66eb74df` + `ae0b4f07` Android port | Kingfisher | no | issue first; large parts can never leave the fork |
| `058eb5d4`, `2296a263`, `07f72deb`, `731194ee` Android first-frame work | Kingfisher | no | part of the port, and depends on skip-ui `23154a0`. `07f72deb` replaces most of the first two. `731194ee` sits on the *target*-cache-hit path; #2572/#2573 rewrote the *original*-cache-hit path beside it, and `239c970b` merged them without touching it |
| `fb0ef04` `Defaults.defaultSuite` | Defaults | no | issue first; re-pitch without the Android rationale |
| `4c1ad29` drop macros + guards | — | — | fork-only, permanently |
| `e67bf25` + `4f7ad45` Android `@Default` | — | — | nothing to send: the second commit moved it out of the fork again, so the pair is a no-op against upstream |
| `cfa7d82`, `64de0f8` fork re-points | — | — | fork-only, and load-bearing: they are what gives skip-ui one location across the graph. They retire with the patches above |
| `9ed3eca`, `43ffce6`, `a6d70f1`, `b0fc5c2`, and the matching commits in skip-ui, skip-fuse-ui and skip-web | — | — | the same for skip-foundation, in skip-bridge, skip-model, skip-android-bridge and skip-fuse. They retire with the skip-foundation patches |

## Before any PR

- **Draft only.** Repeated because it is the rule most easily read past.
- **A fork must be a real GitHub fork** (a `parent`, inside upstream's repository
  network), or GitHub cannot open a cross-repo PR from it. All five PR-raising forks are.
  A repository created by push is fixed by recreating it with `gh repo fork` and pushing
  `android` back; URLs and SHAs are unchanged. `Ceylo/skip-web` is not a fork and never
  raises a PR — see [skip-web](#skip-web).
- **Never PR the `android` branch.** One topic branch per patch, cut from the current upstream
  default, rebased onto it — not merged. A PR carrying seventeen unrelated commits is the
  single most reliable way to be ignored.
- **Strip the `Claude-Session:` trailer** from commits that go upstream: those URLs are dead
  links for a maintainer. Keep `Co-Authored-By`. The fork commits keep their trailers; only
  the topic-branch copy loses it (`git commit --amend --reset-author`, message rewritten).
  Check with `git log upstream/main.. --format=%B | grep Claude-Session`. Commits are
  authored as `451334+Ceylo@users.noreply.github.com`, so no personal address is exposed.
  **Exception, by Ceylo's decision:** skip-ui #524 and skipapp-showcase #122 carry no
  `Co-Authored-By` either; AI use is disclosed in the template's checkbox instead.
- **Rewrite the app-specific comments.** The Kingfisher fork's `Sources/` names FurAffinity
  in one place since #2576 replaced the `DownloadTask` doc comment (2026-09-13): a
  `KFImage.swift` comment about cap insets. A library shouldn't know about one app, so
  rewrite it to state the general case before the patch goes out, then check the branch
  diff with `git diff upstream/master | grep -i -e furaffinity -e android`.
- **Search the target's open PRs *and* issues for the same surface first**, and link whatever
  you find. skip-ui #468 was closed as obviated by #471, and Kingfisher #2570 closed as
  covered by #2568 — both authors had written the whole thing first.
- **Run `/code-review` before every push that reaches a PR**: the first push that opens it,
  and every review-round fix. The order is tests green → review → address findings → push
  → PR. Review the *patch*: the local topic branch in the upstream clone, against upstream's
  default branch. A PR URL is the wrong target here, because the commits aren't on it yet.
  Never review the FurAffinity worktree's current branch, which is what a bare
  `/code-review` reviews. Fix what the review confirms, or say in the PR body (or the
  review reply) why a finding doesn't apply. Nothing is pushed with unaddressed findings.

## The PR body

Five sections, in this order, and short. Maintainers read many of these.

```markdown
## What
Behaviour before, behaviour after. Two sentences.

## Before / after
| before | after |
|---|---|
| ![](…) | ![](…) |

## Side effects
- <effect> — screenshot if it is visible; otherwise the case that was checked and found unchanged.

## Verified
- <what actually ran>
```

Plus the repository's own checklist where it has one. Don't tick a box whose step didn't run.
skipapp-showcase has no test targets, so its `swift test` box stays unticked, with the reason
given.

Images go on an orphan `pr-assets/<topic>` branch in the fork, scaled to 400 px wide and
referenced as `raw.githubusercontent.com` URLs. `gh` cannot upload attachments. Check each
URL with `curl -sI` for a 200.

The `Verified` list and every screenshot are outputs of [Producing the
evidence](#producing-the-evidence). None of it is written from memory.

## Producing the evidence

The PR body may only claim what this produced. No line of `Verified` is written before its
step has run.

**Setup, once — the harness is `~/Development/SkipUpstream/`** (built 2026-09-13). Showcase no
longer has ShowcaseLite/ShowcaseFuse targets: one app, switched by `SKIP_MODE=lite|fuse`, and
`SKIP_DEPENDENCY_ROOT=<dir>` repoints *every* `skip*` dependency at `<dir>/<repo>` — so that
directory holds every Skip repo the graph reaches, not just the patched two. There:

- `skip-ui/`, `skip-fuse-ui/` are `git worktree`s of the `~/Development/SkipForks/` clones at
  upstream `main`; the rest are shallow clones. Only a missing repo breaks resolution.
- `build-showcase.sh lite|fuse [build|launch]` — iOS for a simulator plus the Android app
  through Gradle, one DerivedData per mode (SwiftPM won't re-evaluate a manifest because the
  environment changed). `launch` installs onto the emulator: wrap it in
  `with-emulator-lock.sh`.
- `drive-android.sh` taps by visible text (`scrollto:`, `tapprefix:`, `longpress:`, `dump:`,
  `shot:`); `menu-item-colors.py` reads a text colour from a screenshot + its dump.
  `symbol-evidence.py` crops every row of a scrolling playground by its label, so two runs
  can be compared row by row even when a row's height changes; `ios-symbol-rows.py` does
  the same on the simulator. For a `//􀀀` glyph comment, match the rendered
  `NSImage(systemSymbolName:)` against SF Pro's private-use glyphs, and check the match on
  a comment already known to be right: the fork's guesses were wrong.
- Evidence and logs land in `evidence/` and `logs/`.

Build both modes *before touching anything*: a broken baseline is indistinguishable from a
broken patch. Then grep the build log for `SkipUpstream/skip-ui/Sources` — a stale remote
checkout sits in DerivedData too, and only the log shows which one compiled. In Fuse, the
installed APK must contain `libSkipFuseUI.so`. A one-off `CopySwiftLibs … No such file or
directory` in the iOS half is a race: re-run before reading anything into it.

Take iOS screenshots with the app launched `-AppleLanguages "(en)"`; the simulator is French.

Harness drift seen on 2026-10-04, all local to `~/Development/SkipUpstream/`:
- Showcase `main` did not build against the dependencies' current `main`s (skip-kit #46 removed
  `SBOMView`, which Showcase still uses; Fuse also failed on a duplicated static `SkipFFI`). The
  evidence was built on Showcase `c2e4ab3` with the dependency checkouts at their clone commits.
  The playgrounds touched are unchanged between the two, so the PR branches are still cut from
  `main`.
- `AlertPlayground` times out the type checker in this Xcode; it is stubbed in the working tree
  (`logs/alert-playground-harness-stub.patch`), never committed.
- This Xcode keeps SimulatorKit under `SharedFrameworks`, so `xcodebuildmcp ui-automation`
  needs a `DEVELOPER_DIR` shadow of `Xcode.app` with a `PrivateFrameworks/SimulatorKit.framework`
  symlink. `ios-tap.sh <sim> <label>` scrolls to a label and taps it.
- `SKIP_UI_DIR=<checkout> mutation-run.sh …` runs the tests from another `skip-ui` worktree, so a
  test run never swaps a file under a Showcase build. In `drive-android.sh` steps, `~` is a space.

**Per patch:**

1. **Write the Showcase playground** that exercises the patched surface — a
   `<Name>Playground.swift` registered in `PlaygroundListView.swift`. It is the third PR of
   the pair anyway, and it is what makes the before/after reproducible by someone else.
2. **Capture *before*** on the unpatched packages, both platforms:
   ```
   Scripts/Android/with-emulator-lock.sh adb exec-out screencap -p > before-android.png
   xcrun simctl io "$(Scripts/iOS/simulator.sh --udid)" screenshot before-ios.png
   ```
3. **Apply the patch.** `swift test` in each package, then **build the Kotlin through
   Gradle**. `swift build` only transpiles; skip-ui #506 was closed because its author
   stopped there and the change did not compile.
4. **Capture *after*** — same playground, same device, same frame.
5. **Walk the side effects deliberately.** Re-shoot the neighbouring playgrounds the patch
   can plausibly reach and record what was checked even where nothing moved. `forks.md`
   already names the blast radii: a `Text` overload can capture string literals app-wide, a
   `listRow*` precedence change reaches every list, the `ScrollView` fill changes large-title
   collapse. "No side effects" with nothing behind it is the claim a reviewer tests first.
6. **Now** write `Verified`, naming the emulator API level and the simulator device, and
   attach steps 2, 4 and 5.

**Semantics are not appearance.** `6f06ae4` made disabled menu items `enabled=false` and
untappable, and still drew them at full colour: SkipUI passes an explicit tint that overrides
the Compose component's own disabled colours. Read a pixel, not the uiautomator tree. And a
fork patch is not a finished upstream patch — the upstream branch grew the dimming, the fork
did not.

**Where skip-ui has a Robolectric test for the surface, add one next to it** and prove it with
a mutation run: revert the source file to `origin/main`, confirm the new test fails *for its
own assertion* (read the message, not just the count), restore.

**Where there is no visual** — Kingfisher's `init(cancelling:)`, `Defaults.defaultSuite` —
the before/after pair becomes a failing-then-passing test with its real console output, plus
the platform matrix that ran. Say that the substitution was made; an empty screenshot
section reads as a skipped step.

For an **access-level** change, a test in the repo proves little: `@testable import` already
reaches the internal symbol. The real before/after is a throwaway SwiftPM package outside
the repo that depends on the library by `path:`, with no `@testable`. Run `swift build`
against a `git worktree` of upstream's default branch, then against the topic branch, and
quote the compiler error.

## skip-ui + skip-fuse-ui

One section: they are always paired.

### Gates

- <https://skip.dev/docs/contributing/> is canonical, including the worked three-PR example
  (skip-ui #356 / skip-fuse-ui #93 / skipapp-showcase #74).
- **The CLA is signed.** `Ceylo` was added to
  [`skiptools/clabot-config`](https://github.com/skiptools/clabot-config)'s `.clabot` by
  [#98](https://github.com/skiptools/clabot-config/pull/98), merged 2026-09-13 (`23abce5`).
  Until then it blocked review before anything else, which is why the first draft went to
  Kingfisher; it stopped #516, #503 and #478 dead. If cla-bot flags a code PR anyway, comment
  `@cla-bot recheck`.
- **CLA scope: nothing from the app goes into a Skip PR.** Skip's CLA grants a perpetual,
  irrevocable, sublicensable licence with no outbound commitment, so Skip may relicense a
  contribution under any terms. `Ceylo/FurAffinityApp` has no licence and stays all rights
  reserved, which holds only while none of its code is submitted. Write Showcase playgrounds and
  patches from scratch rather than lifting app code (e.g. `FAKit/RichText/`), and check the
  topic branch's diff for anything derived from it before pushing.
- skip-ui's `.github/pull_request_template.md` is required: CLA signed, `swift test` run, and
  "does this need a paired skip-fuse-ui PR" answered. It also asks whether **AI was used**,
  how, and how the change was verified by hand — Ceylo's to answer.
- **Any change to API surface — including removing an `@available(*, unavailable)` — needs
  the paired fuse-ui PR** plus a Showcase playground. Cross-link all three bodies.
- `skip-fuse-ui/ADDING_MODIFIERS.md` fixes branch naming (`feature/<x>-modifier`,
  `feature/<x>-playground`), file locations, and the `modifierChain`-vs-`ModifierView` split
  whose failure mode is a modifier that "compiles but does nothing on Android".

### What the merged PRs did well

Single purpose, one or two files, merged in one to seven days: #496, #479, #477, #476, #467,
#465, #454, #455. They name the issue they fix (#473 → #472) and explain the *Compose-side*
mechanism rather than the SwiftUI intent.

#453 is the model for answering a `CHANGES_REQUESTED`: tests written in the repo's own idiom,
a mutation table showing each case fails only for its own reason, and the existing
`XCTSkip("… inconsistent font rendering on different emulators")` wording reused rather than
invented.

### What the rejected PRs missed

- **#506 did not compile.** `swift build` transpiles without compiling the Kotlin; the error
  only appears at Gradle time. This is step 3 above, and it is the most common miss.
- **#468 duplicated #471** — nobody read the open PRs.
- **#464 and #407** were superseded by fixes landing elsewhere while they sat.
- **#478** argued from one app's needs ("disable it temporarily for Algumon") with no general
  case.
- **#516** was filed by an agent without its author asking for it, on an unsigned CLA.

### Keeping it moving

Merges arrive in batches around releases — clusters on 2026-06-17, 07-01, 07-17/18, 08-19 —
so a patch wants to be finished *before* a batch, not just after one. Open as a draft and
hand it over complete: paired PRs, playground, screenshots, `Verified`. #434 is what an
*abandoned* draft costs (three months, nothing else wrong with it), which argues for
finishing fast, not for opening ready.

Do not leave a cross-repo dependency dangling — #434 blocks on skip-foundation #122. Once
Ceylo has marked a PR ready, ping @marcprux after about two weeks of silence; #500's "I think
this may have fallen through the cracks" is the precedent that worked.

**Expect red CI on the fuse-ui PR** whenever the API surface changes: skip-fuse-ui builds
against the last skip-ui *release tag*, not `main`. The Skip docs say so explicitly. Note it
in the body so it is not read as a failure.

### Known collisions

Re-check these before sending anything from the text stack (states as of 2026-10-11).

| PR | Overlaps |
|---|---|
| skip-ui [#453](https://github.com/skiptools/skip-ui/pull/453) (merged 2026-10-03) + skip-fuse-ui [#118](https://github.com/skiptools/skip-fuse-ui/pull/118) (open) | `cad81a8` / `967a19a` — an independent `Text + Text` run model. Since the 2026-10-19 fork merge `_Text` carries both (`runs` rendered first); ours goes once #118 lands and the app's `+` can use #453's runs |
| skip-ui [#434](https://github.com/skiptools/skip-ui/pull/434) (draft) | `1d56dc9` / `f0e4d6c` — real `AttributedString` rendering, depends on skip-foundation #122 |
| skip-ui [#436](https://github.com/skiptools/skip-ui/pull/436) (open) | `bf0c6ad` — rewrites `Text` link handling onto `LinkInteractionListener`, which our HTML path also relies on |

## Kingfisher

### Gates

`CONTRIBUTING.md`: explain what the code does *and how to execute it*, include tests, keep it
small ("the bigger the pull request, the longer it will take"), and give the motivation —
"What was the purpose? Why does it matter to you?".

`docs/development.md` is the style contract: the license header on every file, the
`KFCrossPlatform*` typealias pattern, `Sendable` annotations, the `.kf` namespace wrapper.
There is no PR template. The repo carries its own `AGENTS.md` (`CLAUDE.md` is now just a
pointer to it). Read it: the maintainer works with agents himself, and reviews arrive from
his assistants (@onevclaw, @onevpaw, @onevtail) citing exact commit SHAs. Answer at that
level of specificity.

`CHANGELOG.md` is the maintainer's. Its last 20 commits are all onevcat's, so a
contributor's PR doesn't touch it.

**Tests, as of 2026-09-12.** Nocilla stubs HTTP. Two sets of destinations exist, and neither
matches upstream's `docs/testing.md` (iPhone 15 / 17.5), which is out of date:

- `bundle exec fastlane tests`: macOS, iPhone 16 / 18.5, Apple TV / 18.5, and a *build*
  only for Apple Watch Series 10 (42mm) / 11.5.
- CI (`.github/workflows/test.yaml`, what the PR is judged on): Xcode 26.2 and 26.6 ×
  {macOS, iPhone 17, Apple TV 4K (3rd generation), `-sdk watchsimulator` build}, at OS 26.2 /
  26.5. **Match this one.**

The lanes need Ruby 3.3.6 (`.ruby-version`). The system Ruby here is 2.6.10; without it, run
the lane's own `xcodebuild` arguments directly (`-workspace Kingfisher.xcworkspace -scheme
Kingfisher SWIFT_VERSION=5.0`) and say so in `Verified`. The tvOS runtime was not installed
by default; `xcodebuild -downloadPlatform tvOS` fetched 26.5 (3.8 GB). watchOS needs only
the SDK.
One upstream tvOS test, `testRetrieveImageWithAsyncCacheTypeCheckUsesOriginalCacheFallback`,
times out 2 runs in 20 on `master` too: re-run it before reading a failure into it.

### What the merged PRs did well

One bug, one mechanism, tests attached, merged in days: #2561, #2556, #2540, #2539. Outside
contributors merge routinely here — this is not a closed shop (#2572, #2571, #2569, #2565 and
#2563 in August–September 2026 alone).

### What the rejected PRs missed

- **#2545 was declined with a reproduction.** onevcat DYLD-interposed `malloc` to show the
  root cause was elsewhere — and thanked the author for being upfront about verification
  status, saying it made the PR easier to evaluate. Evidence beats plausibility, and stating
  what you did *not* verify is rewarded rather than penalised.
- **#2517** proposed a design that needed a public-protocol change the protocol did not have;
  onevcat took the idea and rebuilt it his own way with async cancellation. Anything
  protocol-shaped gets an issue first.
- **#2570** duplicated #2568.
- **Reviews exercise new API against existing options.** Anything that reports errors or
  cancellation gets tested with `.alternativeSources` and a retry strategy too, not only on
  its own.

### Other requirements, and the platform reality

`Package.swift` declares Apple platforms only, and nothing in the tracker suggests interest
in Android. So:

- **The Android port gets an issue before any code.** Skip's own docs encourage submitting
  Android-compat PRs to third-party libraries so they earn the Swift Package Index Android
  badge, which is the argument to make — but it is onevcat's call, and the skipstone plugin,
  the unconditional `SkipFuseUI` dependency and the `Documentation.docc` deletion can never
  go upstream regardless. The fork survives either way; the question is only how thin.

### Keeping it moving

Under ~200 lines, tests included, the issue named, verified across all four Apple platforms,
and an explicit account of what was and was not checked.

A first-time contributor's workflows don't start on their own: they sit at
`action_required` until a maintainer approves them, so "no checks reported" is not a CI
result. Read the state with
`gh api "repos/onevcat/Kingfisher/actions/runs?branch=<topic-branch>"`.

## Opened PRs

State is one of draft / opened / merged / rejected / closed, as of 2026-10-21; refresh it with
`gh pr view <n> -R <repo> --json state,isDraft`.

| PR | Patch | State |
|---|---|---|
| skipapp-showcase [#122](https://github.com/skiptools/skipapp-showcase/pull/122) | playground for skip-ui #524 | opened |
| skipapp-showcase [#123](https://github.com/skiptools/skipapp-showcase/pull/123) | playground rows for skip-ui #525 | opened |
| skip-fuse-ui [#151](https://github.com/skiptools/skip-fuse-ui/pull/151) | private `@State`/`@Environment` bridging, runtime half (write-up on branch `android-skip-private`) | opened; merges before skipstone #282 |
| skipstone [#282](https://github.com/skiptools/skipstone/pull/282) | private `@State`/`@Environment` bridging, generator half | opened |
| skip-ui [#539](https://github.com/skiptools/skip-ui/pull/539) | `88ac81d` | opened |
| skip-ui [#540](https://github.com/skiptools/skip-ui/pull/540) | `1335ebf` + `22ff079`, reworked in review | opened |
| skip-ui [#541](https://github.com/skiptools/skip-ui/pull/541) | `4b30753`, vertical half | opened |
| skip-ui [#548](https://github.com/skiptools/skip-ui/pull/548) | `f54f6e8`; rows added to showcase #123 | draft |
| skip-ui [#549](https://github.com/skiptools/skip-ui/pull/549) | `5110e81`, re-cut without `insets` | draft |
| skipapp-showcase [#139](https://github.com/skiptools/skipapp-showcase/pull/139) | Row Modifiers page for skip-ui #549 | draft |
| skip-ui [#550](https://github.com/skiptools/skip-ui/pull/550) | `524153a`, reworked in review | draft |
| skip-ui [#551](https://github.com/skiptools/skip-ui/pull/551) | `ad375fb` | draft |
| skip-ffi [#14](https://github.com/skiptools/skip-ffi/pull/14) | CI: `SKIP_DYNAMIC_LIBRARIES` gate ([CI instabilities](#ci-instabilities)) | closed: Showcase went green without it |
| actions [#23](https://github.com/skiptools/actions/issues/23) (issue) | the plan every Intel-exit PR links to | opened |
| actions [#22](https://github.com/skiptools/actions/pull/22) | CI: emulator guard reads `runner.arch` ([Leaving Intel macOS](#leaving-intel-macos-runners)) | merged 2026-10-21, in `v1` |
| skip-ffi [#15](https://github.com/skiptools/skip-ffi/pull/15) | CI: `macos-26` + Ubuntu; actions #22 now in `@v1` | opened |

## CI instabilities

Red CI unrelated to a PR costs the maintainer a check on every PR. Scope: the repositories we
send PRs to. Every failed run from 2026-09-04 to 2026-10-04 was classified by failing step and
log signature:

| Instability | Hit | Root cause | Fix |
|---|---|---|---|
| skipstone `android-ci`: APK install on a half-booted emulator (`Can't find service: package`, `system providers not installed`) | ~110 jobs in a month | a blank `sys.boot_completed` taken as booted | fixed by our skipstone #288 (merged 2026-10-13), which also raised the launch timeout 300 → 900 s: Intel launches waited 6–14 min, so that leaves under a minute of margin. Still unfixed: a post-boot `system_server` loss (`Can't find service: package` 30 min after boot) |
| skipapp-showcase Fuse "Export project": `SkipFFI-product` linked as a static library by three images | every Fuse run 2026-09-27 to 2026-10-19 | skip-ffi lacked the `SKIP_DYNAMIC_LIBRARIES`/`SKIP_BRIDGE` gate the other libraries got | gone since skipapp-showcase #141 (2026-10-19), skip-ffi still 1.2.3; our skip-ffi #14 closed as no longer needed |
| Network blips in `setup-skip` (tap clone, `skip android sdk install`) and in `skip export`'s package fetch | ~8 | no retries | setup-skip is being rewritten by actions#20: a comment there, not a PR; the export side fits skipstone #283's `runCommand(retryingOn:attempts:)` later |
| A connected Android test hangs (skip-ui #548: 116 min against 13–22) | 1 | no step timeout in `skip-framework.yml` (job: 180 min) | branch `fix/connected-test-timeout` at 90 min, not sent: the slowest green connected step sampled across nine Skip repos took 50 min (skip-av), so the planned 60 was unsafe, and a timeout only fails a hung job sooner |

Not instabilities: skip-fuse-ui paired PRs compiling against the last skip-ui release
(structural, see above); Kingfisher's red runs (workflow refused for fork PRs, zero jobs).

### Leaving Intel macOS runners

Skip's CI defaults to `macos-26-intel`. The plan is actions #23. GitHub's 2025 notice dated the end of
x86_64 macOS at fall 2027, but `macos-26-intel` shipped since with no end date: argue speed and
queues, not a deadline. Each PR opens with its purpose and gains, and says where its emulator
tests run. Findings (2026-10-04), each from a fork run:

- **No emulator on arm macOS runners.** `HVF error: HV_UNSUPPORTED` on `macos-15` and
  `macos-26`, API 28 and 34; `emulator -accel-check` says HVF is fine regardless. Emulator work
  goes to `ubuntu-24.04` (KVM).
- **`skip-framework.yml`'s arm guard never worked**: `env.RUNNER_ARCH` is always empty in an
  `if:` (the `env` context excludes runner variables). actions #22.
- **Intel queues dominate.** skiptools shares one org macOS concurrency pool: Intel jobs waited
  10–56 min (skip-ffi) and up to 7.9 h (skipstone) to start. Fork runs don't share that pool,
  so their few-second arm queues predict nothing.
- **skip-ui / skip-fuse-ui can't move yet.** The musl skip binary segfaulted transpiling SkipUI
  (128 KiB thread stacks; fixed by our skipstone #290, merged 2026-10-11, and their Android build then takes 32 s /
  57 s on Linux against 91 s / 180 s on Intel). Their host `swift test` still fails on Linux:
  `no such module 'CoreGraphics'` (skip-ui), duplicate static Skip products (skip-fuse-ui).
- **Fuse doesn't build on Linux** (skipstone `android-ci`): duplicate static products, then a
  skip-android-bridge compile error with `SKIP_DYNAMIC_LIBRARIES=1`. Hence the `macos-26-intel` leg skipstone #300 kept (it folded our #289 in).
- Coverage was checked per PR with `~/Development/SkipUpstream/ci-ledger.py OWNER/REPO RUN…`,
  which counts executed tests per step and prints each step's summary sequence. Fork runs need
  a fork-only commit (push trigger, or a caller pointed at `Ceylo/actions@<branch>`): the
  skip-ffi and skipstone forks never registered upstream's workflows, so `gh workflow run` 404s.

## Defaults

### Gates

[`sindresorhus/.github/contributing.md`](https://github.com/sindresorhus/.github/blob/main/contributing.md):
open an issue first for anything large; no unrelated changes; adhere to existing style; add
tests, docs and readme entries; squash before submitting; branch, never `main`; tick "Allow
edits from maintainers"; reference `Fixes #123`; bump after a couple of weeks of silence.

`.editorconfig` is **tabs**, LF, trimmed trailing whitespace, final newline — `.swiftlint.yml`
applies too. Every public symbol is documented in `readme.md`, so a new one is a code change
*and* a readme change.

### What the merged PRs did well

Tiny and mechanically obvious, frequently merged the same day: #223, #215, #201, #202, #182,
#180.

### What the rejected PRs missed

He rejects on **API taste, not correctness**:

- **#187** — "I don't think this is the optimal way to solve this problem", with the
  platform-native alternative named instead.
- **#155** — he questioned whether the initializer "carries its own weight" and proposed a
  simpler shape.
- **#128** — a long, genuinely collaborative design conversation, then closed into an issue
  when the ecosystem moved.

So `fb0ef04` goes as an **issue proposing the API shape before a line is written**, pitched
as what it is for an Apple-only package: one app-group suite as the default for every key,
instead of threading `suite:` through every declaration. The Android motivation currently in
the doc comment is not an argument here and comes out.

### Keeping it moving

Small PRs get same-day replies; design PRs run for months (#225 sat three months and was
resolved by him shipping his own release). Keep it to one public symbol plus its readme entry.

## skip-web

Nothing to upstream, and this fork never raises a PR — but it is **required**, and it is not
a scratch repository. Its `android` branch is upstream plus dependency locations, no source,
for the reason in [forks.md § One location per
identity](forks.md#one-location-per-identity).

So it retires exactly when the skip-ui and skip-fuse-ui patches land upstream and the graph
can name upstream skip-ui again — not before. `Ceylo/Kingfisher` and `FAKit` carry the same
declaration for the same reason.

One thing not to mistake for fork work: the `eval-json` and `inject-function` branches in
this repository are upstream's own, every commit authored by marcprux, for skip-web PR #28
(merged) and #34 (closed).
