# Login and the long-lived WebView

The logged-out screen is the shared `HomeView`. Four things in it needed handling,
each one of the general [rules for shared sources](shared-sources.md#rules-for-shared-sources):

| In HomeView | Guard |
|---|---|
| the Liquid Glass button branch | `#if FA_SKIP_MODULE` takes the pre-iOS-26 capsules (`legacyButtons`): `#available(iOS 26, *)` is true off-Apple, and `GlassButtonStyle` is unavailable |
| `ErrorDisplay`, `NotificationCoordinator` | `#if !FA_SKIP_MODULE`; errors reach the user through `AndroidRootView`'s banner |
| the six `@State`/`@Environment` wrappers | internal, not private |
| `UIApplication.shared.applicationState` | dropped from a log line that already carries `scenePhase` |

`FAKit/Sources/FAKit/Android/FALoginView+Android.swift` substitutes for FAKit's WebKit
login view with the same public surface (`session` binding, `onError`, `makeSession()`).
It lives in FAKit, next to its twin, because only a skipstone module gets a bridged
view's `@State` glue.

## Why a hidden WebView is mounted for the whole session

`FAWebSessionView` (`FAWebSession.swift`) keeps a hidden, hit-testing-disabled WebView
at the root of `AndroidRootView` for the life of the app, as `RootView` does with
`FAChallengeView` on iOS, because:

- `cf_clearance` is bound to the byte-exact WebView User-Agent, read from a live WebView.
- `FAHTTPDataSource`'s fallback for a challenged request navigates a cleared WebView
  and reads the DOM.

`FAWebSession.shared` owns the navigator, and `establishSession()` always runs against
it. Cookies are process-global on Android (`CookieManager`), so it sees whatever the
login sheet just earned. `makeSession()` (autologin) first `awaitReady()`s its first
`onNavigationFinished`: a navigator with no attached engine returns an *empty cookie
list*, not an error, so skipping the wait silently looks logged out.

Waiting for the engine alone is not enough, though it would save ~1.8 s. Measured
2026-10-11 on a cold-booted emulator: a feed request sent once the engine attached,
before that first page load, got a 403 on all 10 launches, carrying the same
`cf_clearance` that got a 200 right after the load. The challenge repair then cost
4–5 s (first thumbnail 3.5 s → 5.6 s). The hidden WebView's page load is what renews
Cloudflare's trust; it is not just a readiness check.

It is **full-size, occluded by the opaque app background**, not 1×1: in a 1×1 frame the
viewport is 4 CSS pixels wide, Turnstile's container measures 0 × 69, and a managed
(passive) challenge can never complete. Cost: the hidden view loads FA's home page,
ads and all, once per launch.

## The WebView User-Agent carries the app identifier

FA staff identify this app's traffic by a `ceylo.FurAffinityApp/<version>` suffix on
the User-Agent. iOS appends it via `applicationNameForUserAgent`; Android through
skip-web's `customUserAgent`, computed once in `FAWebViewUserAgent` from
`FAUserAgent.applicationName`.

**All three `WebEngineConfiguration` sites must carry it** (`FALoginView`,
`FAChallengeView`, `FAWebSession`): the clearance is bound to the exact UA and the jar
is shared, so one site minting under the bare UA 403s everything after. Everything
downstream still reads the UA *live* out of the WebView (`liveUserAgent()`), which stays
the single source of truth; `[CFDIAG] User-Agent drifted=` compares the two. Setting
`customUserAgent` does **not** empty `navigator.userAgentData` (measured).

The suffix embeds the app version, so **an app update invalidates a persisted
`cf_clearance`**: the first launch after one shows `[CFDIAG] cf_clearance drifted=true`
and a round of 403s until it is re-minted.

`Bundle.main.infoDictionary` is empty in a Skip Fuse module, so the version comes from
the package manager (`AndroidAppInfo.versionName`, over `FAAppInfoBridge`), installed
into `FAAppVersion.override` from `onInit()`.

## What draws a challenge, and what doesn't

- **The token, not the client.** A clearance the WebView earned, replayed from the Mac
  by plain `curl --http1.1 -4` with the same UA and cookies, loaded FA 6/6; without
  cookies, 403. An HTTP client that is not a browser is fine once it carries a valid
  clearance. Nothing argues for a different HTTP stack or more header tuning.
- **Not the emulator or its address**: emulator Chrome loaded the page on the same
  egress IPv4 while the app was refused.
- **`cf_chl_rc_ni`**, Cloudflare's re-challenge counter, had climbed to 33 in the jar,
  announcing 33 failed passive challenges on every navigation. iOS never presents it:
  its challenge WebView starts from a cleared jar seeded with auth cookies only.
  Android's `FAWebSession.clearCloudflareCookies()` meant to expire the Cloudflare names
  before a challenge retry, but it **removes nothing**, measured 2026-09-20:
  `cf_clearance` is HttpOnly, which `CookieManager.setCookie` may not overwrite, and
  skip-web emits a `Domain=` for the host-only `cf_chl_rc_ni`, so the expiry names a
  cookie that doesn't exist. Getting rid of the counter needs a way into the HttpOnly
  store; the full-size viewport above is what lets challenges complete meanwhile.
- **Duplicate `Cookie:` pairs** were real, fixed by merging on name, and measured as no
  cause.

## One navigation at a time

**All fallback fetches go through `FAWebSession.fetchPageHTML(_:)`.** It navigates the
one shared engine and reads the DOM back, so two at once interleave and one returns the
other's page: a *wrong parse*. `@MainActor` is no defence across `await`s. The gate
chains each fetch behind the previous one, unstructured so a cancelling caller advances
the queue rather than wedging it, and refreshes the cookie header on the way out. If
the queue ever bites, the next lever is per-URL coalescing.

`fetchPageHTML` waits a challenge out in place rather than handing the interstitial to
the parser, retries the navigation, and throws `CloudflareChallengeRequired` when
exhausted.

## The challenge escalation path

`CloudflareChallengeCoordinator` is shared with iOS; Android installs its defaults
through `configure(…)` from `AndroidRootView`, since there is no `UIApplication` and
the cookies live in the WebView's jar. A challenge is [repaired](#repairing-a-challenge-measured-2026-09-01)
(`awaitResolution()`), long before the WebView fallback, because a resolution fixes
every later request where the fallback rescues one. Two stages:

1. **Passive**: `FAChallengeView` mounts under the opaque background and clears the
   challenge with no visible UI, in 1.5–3 s on the emulator. This is what happens in
   practice.
2. **Interactive**: a sheet, entered only when `_cf_chl_opt.cType` reads `interactive`
   or the safety timeout expires: 25 s here against iOS's 8 s, since a managed
   challenge on the emulator can take 15–20 s.

Interaction is detected from `_cf_chl_opt.cType` (one underscore) on both platforms,
not from the checkbox's iframe, which sits in a *closed* shadow root and can never be
found. The captured interstitial is a fixture
(`www.furaffinity.net:cloudflare-managed-challenge.html`) for
`FAChallengeViewDOMTests`. `AndroidRootView` reads the stage flags off the coordinator
directly, as iOS's `RootView` does (see [Every `@Observable` needs
`SkipAndroidBridge`](shared-sources.md#every-observable-needs-skipandroidbridge-in-scope)).

Cloudflare serves only managed challenges here, so escalation never reaches stage 2 on
its own; tapping the shared `CloudflareResolutionOverlay` pill calls
`markInteractionRequired()` and shows it on demand. The escalate → click → resolve
sequence is covered by `FAChallengeViewDOMTests`.

### Escalation must latch, not return

`FAChallengeView.solveChallenge()` keeps polling after it escalates. It used to
`return` right after `onInteractionRequired()`, which killed the only thing that could
see the user solve the challenge. The decision is
`FAInterstitial.challengeStep(reachedRealPage:snapshot:elapsed:hasEscalated:)`, in FAKit
so it is testable, and its resolution branch sits **above** the `hasEscalated` latch:
the latch silences repeat escalation only, never detection. Stage 2 passes no
`onInteractionRequired`, so it never probes. While stage 1 unmounts, two views can both
reach `markResolved()` → `complete()`, which is idempotent.

## Repairing a challenge (measured 2026-09-01)

Cloudflare judges a **connection** and does not change its mind about one (see
[images.md](images.md#cloudflare-judges-a-connection)), so blind retries are wasted
requests. A challenge is repaired, in this order and no other:

1. **Evict, before awaiting.** A solve takes 1.5–25 s, and every other fetch keeps
   running meanwhile on the poisoned pool.
2. `awaitResolution()`.
3. **Evict again**: connections opened during the solve carry the *old* clearance.
4. **Exactly one retry**, on a freshly pulled cookie header. A second failure goes to
   the WebView fallback, a different mechanism, not another sample of the same one.

Step 4 depends on `AndroidRootView.refreshCredentialsThenRelease()` awaiting
`refreshedCookieHeader()` *before* `markResolved()`; both ends carry a comment, and
`FAHTTPDataSourceTests.retryCarriesTheRefreshedClearance` holds it. Before repairing,
one blind redraw is allowed under h1, where the challenge's `Connection: close` makes a
retry genuinely redial, and none otherwise.

Eviction is guarded by an **epoch**: each request records the pool generation it was
issued against, a challenged caller evicts only if nothing has repaired since, and the
eviction bumps the epoch. Six woken image workers produced one `evicted` and five
`evict skipped, pool already at epoch 1`. The rule lives in
`FAHttpClient.evictIfUnchanged` (`@Synchronized`); `FAConnectionPool` is the one Swift
door to it.

Asking at once instead of after five blind retries cut the time to *ask* for a solve
from ~4 s to 0.7 s (A-B-A, forced challenges), and the worst run's tail to the feed
from 16–26 s to 12 s.

**The repair only works if something can be evicted**, which is why pages and images
share one OkHttp pool. On the old URLSession page path, which exposes no pool, the
post-repair retry was still challenged every time; on the shared client it comes back
200 every time (0% → 100%), and the forced-challenge launch takes no `[CFFALLBACK]`.
"evicted 0 connections" in the log is normal under h1: the challenged connections
already closed, and the epoch bump is the part that matters.

## Forcing a challenge

A relaunch or reinstall keeps the app's data, `app_webview/Default/Cookies` included, so
it keeps the clearance. Edit that DB directly. There is no `sqlite3` on the emulator and
`run-as` cannot read `/sdcard`, so stage through `/data/local/tmp`:

```
PKG=com.example.id1234.<worktree>          # the applicationId, NOT fur.affinity.ui
adb shell am force-stop $PKG               # flush the DB first
adb exec-out run-as $PKG cat app_webview/Default/Cookies > Cookies.db   # exec-out, not shell
sqlite3 Cookies.db "delete from cookies where name in ('cf_clearance','__cf_bm','cf_chl_rc_ni','cf_chl_rc_i');"
adb push Cookies.db /data/local/tmp/C.new && adb shell chmod 644 /data/local/tmp/C.new
adb shell "run-as $PKG cp /data/local/tmp/C.new app_webview/Default/Cookies"
adb shell "run-as $PKG rm -f app_webview/Default/Cookies-journal"
```

Keeping `a`/`b` makes this a *mid-session* re-solve rather than a fresh login. The
challenge then resolves **passively**: the "needs a real click" rule applies to an
interactive Turnstile widget, not to every challenge.
