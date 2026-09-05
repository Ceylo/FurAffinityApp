# Upstreaming the forks

[forks.md](forks.md) records *what* each fork patch does and why. This records how one
travels back to its origin project, so the forks shrink instead of drifting.

Four dependencies are forked, plus a fifth that exists only to re-point two of the others.
Nothing here has been submitted yet; everything below is the process to follow when a patch
is sent.

**The first rule: every pull request is opened as a draft** — `gh pr create --draft`, on
every one of these repositories, without exception. Marking one ready for review needs
Ceylo's explicit approval, each time. Nothing in this document authorises it, and a draft
is never described as submitted.

## Inventory

| Fork | Upstreamable | Stays in the fork |
|---|---|---|
| `Ceylo/skip-ui` | all of it | — |
| `Ceylo/skip-fuse-ui` | all but one commit | `cfa7d82` — names our forks in `Package.swift` |
| `Ceylo/Kingfisher` | `b01358ef` today; the Android port only if onevcat wants one | skipstone plugin, the unconditional `SkipFuseUI` edge, the `Documentation.docc` deletion, the dynamic-library manifest |
| `Ceylo/Defaults` | `Defaults.defaultSuite`, pitched on its own merits | dropping `DefaultsMacros` + swift-syntax, the `#if !os(Android)` guards |
| `Ceylo/skip-web` | nothing | `64de0f8` — one line, retires when the two above land |

Per patch. "Paired" means the change touches API surface and so needs a matching
`skip-fuse-ui` PR *and* a Showcase playground (see [Skip](#skip-ui--skip-fuse-ui) below).

| Patch | Goes to | Paired | Note |
|---|---|---|---|
| `22e8919` `listRowInsets` | skip-ui + `0d5d47a` | yes | un-`unavailable`s API in both repos |
| `5110e81` innermost `listRow*` wins | skip-ui | no | bug fix; SwiftUI-parity argument stands alone |
| `5eee865` + `80c72b4` SF Symbol mappings | skip-ui | no | same shape as merged #476 |
| `1b25638` `FlowRow` | skip-ui + `09a3e69` | yes | new container; `Layout` cannot be emulated, so argue the container |
| `6f06ae4` `.disabled` on menu items | skip-ui | no | bug fix |
| `23ac3bd` menu body text + visible divider | skip-ui | no | **split into two PRs** — the text/icon size and the `outlineVariant` divider are separate fixes |
| `ad375fb` `.subheadline` → `bodyMedium` | skip-ui | no | one token; carries a measured screenshot argument |
| `eaa6abe` resume animation across disposal | skip-ui | no | the recycling-boundary fix; largest single non-text patch |
| `4b30753` `ScrollView` fills its scrolled axis | skip-ui | no | state the large-title side effect in the body — `forks.md` already names it |
| `f4776db` `glassEffect` / `AnyTransition.animation` pass-throughs | skip-fuse-ui | no | fuse-ui only |
| `60671f0` → `1d56dc9` + `f0e4d6c` runs encoder | skip-ui + skip-fuse-ui | yes | **collides**, see below. `60671f0`/`79dc36f` are the superseded markdown cut — do not send them |
| `59f7693` + `de02184` inline content + its link | skip-ui + `737dcfa` | yes | **collides** |
| `193e97c` doc-comment correction on `Text(_:inlineViews:)` | skip-fuse-ui | no | squash into whichever inline-views PR goes; not a PR of its own |
| `bf0c6ad` + `28717f9` HTML via `fromHtml` | skip-ui + `30a2abd` | yes | **collides** with #436 on link handling |
| `cad81a8` `Text + Text` | skip-ui + `967a19a` | yes | **collides** head-on with #453/#118 |
| `9eb2c87` `@_disfavoredOverload` on `Text(AttributedString)` | skip-fuse-ui | no | belongs with whichever attributed-text PR lands; the trap is worth writing up either way |
| `b01358ef` public `DownloadTask.init(cancelling:)` | Kingfisher | no | +11 lines, no platform argument |
| `2b2dc459` + `66eb74df` + `ae0b4f07` Android port | Kingfisher | no | issue first; large parts can never leave the fork |
| `fb0ef04` `Defaults.defaultSuite` | Defaults | no | issue first; re-pitch without the Android rationale |
| `4c1ad29` drop macros + guards | — | — | fork-only, permanently |
| `e67bf25` + `4f7ad45` Android `@Default` | — | — | nothing to send: the second commit moved it out of the fork again, so the pair is a no-op against upstream |
| `cfa7d82`, `64de0f8` fork re-points | — | — | fork-only; they retire with the patches above |

## Before any PR

- **Draft only.** Repeated because it is the rule most easily read past.
- **`Ceylo/Defaults`, `Ceylo/Kingfisher` and `Ceylo/skip-web` cannot raise a PR at all.**
  They are private *and are not GitHub forks* — they were created by push, so `parent` is
  empty and they sit outside the upstream repository network. GitHub only opens a cross-repo
  PR inside a network, and making them public does not join one. Create a real fork and push
  topic branches to it:
  ```
  gh repo fork onevcat/Kingfisher --clone=false
  gh repo fork sindresorhus/Defaults --clone=false
  git -C ~/Development/SkipForks/Kingfisher remote add pr git@github.com:Ceylo/Kingfisher-fork.git
  ```
  `Ceylo/skip-ui` and `Ceylo/skip-fuse-ui` are already public true forks and are PR-ready.
- **Never PR the `android` branch.** One topic branch per patch, cut from the current upstream
  default, rebased onto it — not merged. A PR carrying seventeen unrelated commits is the
  single most reliable way to be ignored.
- **Strip the `Claude-Session:` trailer** from commits that go upstream: those URLs are dead
  links for a maintainer. Keep `Co-Authored-By`.
- **Search the target's open PRs *and* issues for the same surface first**, and link whatever
  you find. skip-ui #468 was closed as obviated by #471, and Kingfisher #2570 closed as
  covered by #2568 — both authors had written the whole thing first.

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

Plus the repository's own checklist where it has one.

The `Verified` list and every screenshot are outputs of [Producing the
evidence](#producing-the-evidence). None of it is written from memory.

## Producing the evidence

The PR body may only claim what this produced. No line of `Verified` is written before its
step has run.

**Setup, once.** Clone the three Skip repos as peers — `skip-ui/`, `skip-fuse-ui/`,
`skipapp-showcase/` — make an Xcode workspace holding both packages plus
`skipapp-showcase/Darwin/Showcase.xcodeproj`, and run **ShowcaseLite** and **ShowcaseFuse**
*before touching anything*: a broken baseline is indistinguishable from a broken patch. The
local packages override the `Package.swift` distributions, which is what makes the workspace
the harness (<https://skip.dev/docs/contributing/> § Local Skip Libraries).

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

**Where there is no visual** — Kingfisher's `init(cancelling:)`, `Defaults.defaultSuite` —
the before/after pair becomes a failing-then-passing test with its real console output, plus
the platform matrix that ran. Say that the substitution was made; an empty screenshot
section reads as a skipped step.

## skip-ui + skip-fuse-ui

One section: they are always paired.

### Gates

- <https://skip.dev/docs/contributing/> is canonical, including the worked three-PR example
  (skip-ui #356 / skip-fuse-ui #93 / skipapp-showcase #74).
- **The CLA blocks review before anything else.** `Ceylo` is absent from
  [`skiptools/clabot-config`](https://github.com/skiptools/clabot-config)'s `.clabot`. PR the
  username in first, then `@cla-bot check` on the code PR. It stopped #516, #503 and #478
  dead.
- skip-ui's `.github/pull_request_template.md` is required: CLA signed, `swift test` run, and
  "does this need a paired skip-fuse-ui PR" answered.
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

Re-check these before sending anything from the text stack; all four were open as of
2026-09-06.

| PR | Overlaps |
|---|---|
| skip-ui [#453](https://github.com/skiptools/skip-ui/pull/453) + skip-fuse-ui [#118](https://github.com/skiptools/skip-fuse-ui/pull/118) | `cad81a8` / `967a19a` — an independent `Text + Text` run model, changes-requested already satisfied |
| skip-ui [#434](https://github.com/skiptools/skip-ui/pull/434) | `1d56dc9` / `f0e4d6c` — real `AttributedString` rendering (draft, depends on skip-foundation #122) |
| skip-ui [#436](https://github.com/skiptools/skip-ui/pull/436) | `bf0c6ad` — rewrites `Text` link handling onto `LinkInteractionListener`, which our HTML path also relies on |

## Kingfisher

### Gates

`CONTRIBUTING.md`: explain what the code does *and how to execute it*, include tests, keep it
small ("the bigger the pull request, the longer it will take"), and give the motivation —
"What was the purpose? Why does it matter to you?".

`docs/development.md` is the style contract: the license header on every file, the
`KFCrossPlatform*` typealias pattern, `Sendable` annotations, the `.kf` namespace wrapper.
Tests are `bundle exec fastlane tests` across iOS/macOS/tvOS/watchOS, with Nocilla stubbing
HTTP. The repo carries its own `AGENTS.md`/`CLAUDE.md` — read them; the maintainer works with
agents himself, and reviews arrive from his assistants (@onevclaw, @onevpaw, @onevtail)
citing exact commit SHAs. Answer at that level of specificity.

### What the merged PRs did well

One bug, one mechanism, tests attached, merged in days: #2561, #2556, #2540, #2539. Outside
contributors merge routinely here — this is not a closed shop.

### What the rejected PRs missed

- **#2545 was declined with a reproduction.** onevcat DYLD-interposed `malloc` to show the
  root cause was elsewhere — and thanked the author for being upfront about verification
  status, saying it made the PR easier to evaluate. Evidence beats plausibility, and stating
  what you did *not* verify is rewarded rather than penalised.
- **#2517** proposed a design that needed a public-protocol change the protocol did not have;
  onevcat took the idea and rebuilt it his own way with async cancellation. Anything
  protocol-shaped gets an issue first.
- **#2570** duplicated #2568.

### Other requirements, and the platform reality

`Package.swift` declares Apple platforms only, and nothing in the tracker suggests interest
in Android. So:

- **`b01358ef` stands on its own merits** and must not be framed as Android work:
  `ImageDownloader.downloadImage` is `open`, but every `DownloadTask` initializer is
  internal, so an override outside the module has nothing valid to return — and
  `KingfisherManager` silently drops the download when the task is not `isInitialized`. That
  is a plain API-consistency bug, provable with a test.
- **The Android port gets an issue before any code.** Skip's own docs encourage submitting
  Android-compat PRs to third-party libraries so they earn the Swift Package Index Android
  badge, which is the argument to make — but it is onevcat's call, and the skipstone plugin,
  the unconditional `SkipFuseUI` dependency and the `Documentation.docc` deletion can never
  go upstream regardless. The fork survives either way; the question is only how thin.

### Keeping it moving

Under ~200 lines, tests included, the issue named, verified across all four Apple platforms,
and an explicit account of what was and was not checked.

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

Nothing to upstream. `64de0f8` re-points `Package.swift` at our skip-ui and skip-fuse-ui
forks and is an artefact of those forks existing; it retires with them. The same is true of
the duplicate skip-ui declarations in `Ceylo/Kingfisher` and in `FAKit` — see
[forks.md](forks.md) on why a package can be one declaration too many.
