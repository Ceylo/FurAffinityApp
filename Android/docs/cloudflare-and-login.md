# Login and the long-lived WebView

The logged-out screen is the shared `HomeView` — same icon, buttons and footer as
iOS, from the same file. Four things in it needed handling, all of them the general
rules in [Rules for shared sources](shared-sources.md#rules-for-shared-sources) applied once each:

| In HomeView | Guard |
|---|---|
| the Liquid Glass button branch | `#if FA_SKIP_MODULE` takes the pre-iOS-26 capsules instead. `#available(iOS 26, *)` is vacuously true off-Apple, and `GlassButtonStyle` is unavailable / `.glassProminent` absent. The capsule pair lives in `legacyButtons` so the `#if` holds balanced braces |
| `ErrorDisplay`, `NotificationCoordinator` | `#if !FA_SKIP_MODULE`; errors reach the user through `AndroidRootView`'s banner, and nothing delivers notifications here |
| the six `@State`/`@Environment` wrappers | internal, not private |
| `UIApplication.shared.applicationState` | dropped from a log line that already carries `scenePhase` |

`FurAffinity/Helper Views/Android/FALoginView.swift` is the Android substitute for FAKit's WebKit one,
matching its public surface (`session` binding, `onError`, `makeSession()`) so the
shared caller compiles unchanged. It cannot live in FAKit — it needs skip-web (see
`FAHTTPDataSource` for the CJNI rationale) — and it is unguarded, so the Darwin
bridge compile finds it too; this module's declaration shadows FAKit's.

## Why a hidden WebView is mounted for the whole session

`FAWebSessionView` (in `FAWebSession.swift`) keeps a 1×1, `opacity(0.001)`,
hit-testing-disabled WebView at the root of `AndroidRootView` for the life of the
app, the way `RootView` does with `FAChallengeView` on iOS. Two things need a live
WebView long after any login screen is gone:

- `cf_clearance` is bound to the byte-exact WebView User-Agent, which is read out of
  a real WebView via JS (a 1 dp one runs scripts fine — verified).
- `FAHTTPDataSource`'s fallback for a challenged request is to navigate a cleared
  WebView and read the DOM.

So `FAWebSession.shared` owns the navigator, and `establishSession()` — cookies →
`OnlineFASession` — always runs against *it*, never against a screen's own WebView.
Cookies are process-global on Android (`CookieManager`), so the hidden WebView sees
whatever clearance and auth the visible login sheet just earned.

`makeSession()` (autologin) first `awaitReady()`s that view's first
`onNavigationFinished`: a `WebViewNavigator` with no attached engine returns an
*empty cookie list* rather than an error, so a cold-launch autologin that skipped
the wait would silently look logged out.

Costs worth knowing: while the login sheet is up there are two WebView instances,
and the hidden one loads FA's home page — ads and all — once per launch.

## The WebView User-Agent carries the app identifier (measured 2026-08-16)

FA staff identify this app's traffic by a `ceylo.FurAffinityApp/<version>` suffix on
the User-Agent; iOS appends it via `WKWebViewConfiguration.applicationNameForUserAgent`.
Android now does the same through skip-web's `customUserAgent`, computed once in
`FAWebViewUserAgent` (`FAWebView.swift`) as the platform default plus
`FAUserAgent.applicationName`, so the suffix can't drift from iOS's.

**All three `WebEngineConfiguration` sites must carry it** — `FALoginView`,
`FAChallengeView`, `FAWebSession` — because `cf_clearance` is bound to the byte-exact
UA while the cookie jar is process-global: a clearance minted by any one of them is
replayed by all. Leaving one un-overridden mints under the bare UA and 403s everything
after. skip-web applies it at engine construction, so no navigation can precede it.

Everything downstream still reads the UA *live* out of the WebView
(`FAWebSession.swift` → `liveUserAgent()` → `FAHTTPDataSource` and
`CoilImageLoader.configure`). The computed string is an input to the WebView only; the
WebView stays the single source of truth. `[CFDIAG] User-Agent drifted=` in the
challenge diagnostics compares the two.

Three earlier comments claimed setting `customUserAgent` "empties
`navigator.userAgentData`, which Cloudflare reads as a bot signal". **Measured false**:
with the override in place the emulator reports
`{"mobile":true,"platform":"Android","brands":[…Android WebView 151, Chromium 151]}`,
and a cold launch clears the challenge and loads the feed with thumbnails. No
`WebSettingsCompat.setUserAgentMetadata` and no fourth skip-web fork are needed.

One expected consequence: the suffix embeds the app version, so **an app update changes
the UA and invalidates any persisted `cf_clearance`**. It is re-minted on the next
challenge; the first launch after an update showing `[CFDIAG] cf_clearance drifted=true`
and a round of 403s is that, not a regression.

`Bundle.main.infoDictionary` is *empty* in a Skip Fuse native module (corelibs
Foundation, no Info.plist), so the version behind that suffix comes from
`FAAppInfoBridge.versionName()` — the package manager — and is installed into
`FAUserAgent.appVersionOverride` from `onInit()`, before any WebView exists.

## What actually draws the Cloudflare challenge (measured 2026-08-12)

Two candidate causes were tested and both are settled.

**The duplicated `Cookie` header was real, and was not the cause.** Every request
used to send every pair twice (`FAWebSession` derives the base header and
`OnlineFASession`'s auth cookies from the same jar, and the merge concatenated
them). Fixed by merging on name. An A/B inside one session measured **null** by
the rule fixed before the run; the fix stands on principle, not on that
measurement — no browser sends a pair twice.

**It is not the emulator either.** Same minute, same egress IPv4, emulator Chrome
loaded the full page while the app was refused `403 cf-mitigated: challenge`. It
is not the address, then.

**The hidden WebView cannot solve a challenge, which is the real defect.**
Emulator Chrome cleared the interstitial unattended in under 15 s; the 1×1,
`opacity(0.001)`, hit-testing-disabled WebView sat on `Un instant…` through
three navigations and ~60 s.

## Why the hidden WebView never cleared it (measured 2026-08-12, later)

Dumping what the engine was actually looking at answered it. The interstitial
declares `cType: 'managed'` — the *passive* kind, no click required — and loads
Turnstile with `render=explicit`. `window.turnstile` was present, no JS errors,
every challenge resource fetched 200. Two things were wrong:

**The widget had no room.** Inside the 1×1 frame the WebView's viewport is 4 CSS
pixels wide, and Turnstile's container measured **0 × 69**. Widening the frame
made the same container measure 358 × 69. A widget that cannot lay out cannot
report, so the managed challenge never completed and the page stayed on
`Un instant…` forever. (The widget's own iframe lives in a *closed* shadow root,
so `document.querySelector('iframe[src*="challenges.cloudflare.com"]')` — what
`FAChallengeView`'s DOM probe looks for — can never find it. Measure the
container instead.)

**We kept handing Cloudflare its own escalation counter.** The jar held
`cf_chl_rc_ni`, Cloudflare's *re-challenge non-interactive* count, and it had
climbed to **33**. Every navigation re-presented it, i.e. announced 33 prior
passive failures. iOS never does this: `FAChallengeView` builds its WebView with
`clearCookies: true` and seeds auth cookies only.

Fixing both — a full-size WebView occluded by the opaque app background
(`AndroidRootView`), and expiring the Cloudflare cookie names before each
challenge navigation (`FAWebSession.clearCloudflareCookies`) — took autologin
from never completing to completing on every cold launch tried, feed included.

The two fixes do different jobs, and the counterfactual separates them:

| Viewport | Cookie hygiene | Hidden WebView's own page | Autologin |
|---|---|---|---|
| 1×1 | no | `Un instant…` forever | never |
| full | no | `Un instant…` forever | only via the fallback, slowly |
| 1×1 | yes | `Un instant…` forever | **succeeds** |
| full | yes | real FA index, cleared in place | **succeeds** |

So the cookie hygiene is what makes the app work; the viewport is what lets the
WebView solve a challenge *in place* rather than leaning on the fallback. Note
Cloudflare still decides per request — one of the runs above was challenged on
first contact and recovered through the fallback — so neither fix makes
challenges go away, they make them survivable.

## The control that settles "browser engine vs bare client" (2026-08-12)

The missing control finally ran: take a clearance the WebView earned *after* the
fixes above — one that demonstrably loaded real FA pages — and replay it from the
Mac through plain `curl`, the barest client there is.

| Client | Clearance | Result |
|---|---|---|
| `curl --http1.1 -4`, WebView UA + full cookie header | known-good | **200, 6/6**, ~135 KB, logged in |
| `curl --http1.1 -4`, WebView UA, no cookies | none | 403 `cf-mitigated: challenge` |

**So the bare client was never the problem.** Engine-vs-bare-client was tested
directly and is *not* the discriminator: an earlier Mac-curl run refused 403 under
the app's exact UA and cookies is not reproducible with a *valid* clearance — what
it replayed was a token from a WebView that had never actually solved a challenge,
carried alongside a climbing `cf_chl_rc_ni`. The discriminator is the token, not
the engine. Nothing here argues for a physical device, a different HTTP stack, or
more header tuning.

That also means the WebView-fetch fallback is a backstop rather than the main
road: with a good clearance, `URLSession` is expected to carry page loads.

## One navigation at a time, and when to wipe

Two rules govern the shared engine `FAWebSession` owns.

**All fallback fetches go through `FAWebSession.fetchPageHTML(_:)`.**
`WebViewNavigator.fetchPageHTML` navigates that one engine and then reads the DOM
back out of it, so two at once interleave loads and one fetch returns the other's
page — a *wrong parse*, not merely a slow one. `@MainActor` is no defence: every
`await` inside is a suspension point the other fetch runs at. The gate chains each
fetch behind the previous one, unstructured on purpose so a cancelling caller
advances the queue rather than wedging it, and refreshes the cookie header on the
way out (the navigation that rescued this page may have minted a clearance the
image layer should carry). N concurrent fallbacks become a queue; if that ever
bites, the next lever is per-URL coalescing, not de-serializing.

**`clearCloudflareCookies()` runs before a *retry*, not before the first
navigation.** We reach the fallback because *URLSession* was challenged, which says
nothing about the WebView's own clearance — and dropping it costs every other
request and every image the clearance they were about to replay. Once a navigation
comes back still challenged, the `cf_chl_rc_ni` counter among those cookies is what
the edge escalates on, so the wipe is right from `attempt > 1` on.

Measured over paired cold launches with `cf_clearance` deleted and an uncommitted
`challengeRetries = 1` (so any challenge drops straight to the fallback), same
scroll both times:

| | before | after |
|---|---|---|
| 403 challenge lines | 8 | 1 |
| `asking for resolution` | 5 | 1 |
| `[CFFALLBACK]` lines | 6 | 0 |
| credential pushes | 2 | 1 |

The remaining challenge is the deliberate cold-start deletion. Cloudflare's gate is
probabilistic per request, so one pair carries noise, but 6 → 0 fallbacks is well
outside it. The interleaving the queue prevents was *not* reproducible: across four
forced-challenge runs the emulator never had two fallbacks in flight at once, so
that half lands as a correctness guard rather than a measured fix.

## The challenge escalation path

`CloudflareChallengeCoordinator` is shared with iOS — only its defaults are
per-platform (see the class comment). Android installs its own through
`configure(…)` from `AndroidRootView`, because there is no `UIApplication` and
the cookies live in the WebView's jar rather than `HTTPCookieStorage`.

When `FAHTTPDataSource` exhausts its URLSession retries it now calls
`awaitResolution()` *before* the WebView fetch, because resolution mints a
clearance that fixes every subsequent request, while the fallback only rescues
the one in hand. Then the two stages run:

1. **Passive** — `FAChallengeView` mounts under the opaque background and clears
   the challenge with no visible UI. Measured 1.5–3 s per challenge on the
   emulator, and it is what actually happens: forcing a challenge by deleting
   `cf_clearance` from the jar produced four challenges in one launch, all four
   resolved this way, feed included.
2. **Interactive** — a sheet, entered only when `_cf_chl_opt.cType` reads
   `interactive` or the safety timeout expires. The timeout is 25 s here against
   iOS's 8 s: a managed challenge on the emulator can take 15–20 s, and
   escalating sooner puts a sheet in front of a user it was about to spare.

Two things differ from FAKit's iOS view and are worth knowing:

- **Interaction is detected from `_cf_chl_opt.cType`, not the checkbox's size.**
  FAKit's probe used to measure `iframe[src*="challenges.cloudflare.com"]`, which
  can never match — Turnstile puts that iframe in a *closed* shadow root — and to
  test `window.__cf_chl_opt`, two underscores, where Cloudflare uses one. Both
  platforms now read `cType`. The captured interstitial is a fixture
  (`www.furaffinity.net:cloudflare-managed-challenge.html`) and
  `FAChallengeViewDOMTests` holds the probe's global against it.
- **The stage flags are mirrored into the view's own `@State`.** Reading
  `coordinator.pending` directly recomposes nothing, so `AndroidRootView` keeps
  local `@State` fed by `CloudflareChallengeCoordinator.onStateChange`. The cause
  is import visibility, not cross-module nesting: `CloudflareChallengeCoordinator`
  lives in FAKit, a plain SwiftPM package, so its `@Observable` gets the stdlib
  registrar (see [Every `@Observable` needs `SkipAndroidBridge` in
  scope](shared-sources.md#every-observable-needs-skipandroidbridge-in-scope)). Unlike the
  app-module cases, **this one cannot be fixed with an import.** Adding
  `skip-android-bridge` to `FAKit/Package.swift` was tried and reverted: the iOS
  build survives it fine, but the Android compile fails with `missing required
  module 'CJNI'` — `CJNI` is generated by skipstone, which never processes a
  plain SwiftPM package. The mirror stays until FAKit itself is skipstone-built.

## Escalation must latch, not return

`FAChallengeView.solveChallenge()` polls; it does **not** stop when it escalates.
It used to `return` right after calling `onInteractionRequired()`, which killed
the only thing that could observe the user solving the challenge it had just
escalated to — stage 1 went inert the moment stage 2 appeared, and nothing ever
reported the resolution.

The decision is `FAInterstitial.challengeStep(reachedRealPage:snapshot:elapsed:hasEscalated:)`,
in FAKit so it is testable — the Android app module has no test target. Its
resolution branch sits **above** the `hasEscalated` latch: the latch silences
repeat escalation only, never detection.

Stage 2 passes no `onInteractionRequired` — the sheet *is* the escalation — so it
never probes at all, which also keeps a `_cf_chl_opt` eval every 500 ms off the
sheet's hot path.

Two `FAChallengeView`s are briefly alive while stage 1 unmounts. Both can only
reach `markResolved()` → `complete()`, which is idempotent. Benign.

Still unexercised: the interactive sheet. Cloudflare served only managed
challenges throughout, so stage 2 has never actually drawn, and the
escalate → stay-alive → human-click → resolve sequence is covered by
`FAChallengeViewDOMTests` rather than on-device.

So `fetchPageHTML` no longer hands the interstitial to the parser (which
reported it as a missing element at `FAHomePage.swift:28`, naming a parser line
for a Cloudflare problem). It waits the challenge out in place — reloading
restarts it — retries the navigation, and throws `CloudflareChallengeRequired`
when exhausted. `FAHTTPDataSource` likewise retries `cf-mitigated: challenge`
before paying for a WebView navigation, since the decision is per-request. The
cost when everything is challenged is ~60 s of retries before the error lands
(5 URLSession attempts, then 3 navigations of 8 s polling). That tail is now
useful rather than just slow — the navigations it pays for do clear challenges —
but it is still worth retuning.

One more thing that run turned up: repeated cold launches ANR the app
(`Input dispatching timed out`, main thread blocked ≥15 s) — roughly two thirds
of forced relaunches produced no HTTP request at all and no log past
`updateSession() start`. `establishSession()` is `@MainActor` and awaits
skip-web JNI calls on a WebView that is busy running challenge script. Not
investigated further.
