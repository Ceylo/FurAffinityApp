# Images

iOS gets a memory cache, background decoding, request coalescing and a bounded
download queue from Kingfisher. Android has none of that for free, so the pipeline is
three Android-only pieces:

```
FACoilBridge.kt        OkHttp + coil3's standalone DiskCache. Returns an on-disk PATH.
CoilImageLoader.swift  AnyDynamicObject/JNI driver for it.
FAImageStore.swift     memory LRU, coalescing, concurrency gate, off-main decode.
FAImage.swift          KFImage-shaped view + the prefetch API shared views call.
```

Rules that are easy to get wrong here:

- **Never push a `Cookie:` header that lost its `cf_clearance`.** Coil cannot pull
  a fresh header per request the way the HTTP layer can, so
  `FAWebSession.refreshedCookieHeader()` is the one place that keeps the two in
  step — and a header read *mid-wipe* has no clearance at all. Pushing that
  de-seeds the image layer and every subsequent request's `Cookie:` line, turning
  one challenged fetch into a stampede. The guard is timing-free: if the incoming
  header carries no clearance and the last pushed one did, hand the last-good one
  back. Expiring the cookie locally does not invalidate it at the edge, so
  replaying it is correct, and `pushedCookieHeader` already *is* the last-good
  header — no new state. `String.carriesCloudflareClearance` (in FAKit, so
  `StringFATests` covers it under the iOS gate) matches the cookie *name*: a plain
  `contains("cf_clearance=")` would also accept `xcf_clearance`.
- **Nothing decodes on the main actor.** `.task` on a SwiftUI view is MainActor-isolated,
  so anything after an `await` in it resumes on the main thread. Decoding belongs on
  `FAImageStore`'s queue.
- **Never block on a `Task.detached`.** FurAffinityUI is a *native* Skip module, so a
  blocking JNI call there pins a Swift cooperative-pool thread. Go through
  `FAImageStore`'s gate, which submits to a real `DispatchQueue`.
- **No image bytes cross JNI.** The bridge returns a path; `FAImageStore` decodes it.
- **`UIImage(contentsOfFile:)` needs a `file://` URI**, despite the name — SkipUI
  implements it with `Uri.parse` + `ContentResolver.openInputStream`, and a bare
  filesystem path yields nil with no error.
- **The width passed to `prefetchingPreviews` must be the width the row renders at.**
  `bestThumbnailUrl(for:)` snaps to discrete buckets, so a few dp of difference changes
  the URL and silently voids every prefetch. This is what the `listRowInsets` fork is for.
- **Cloudflare's verdict on an image request is per *connection*, not per request and
  not per header set.** Measured on the emulator with `FACoilBridge.probeHeaders`, a
  4 URL x 5 variant Latin square run inside one launch (`[Probe]` lines):

  | | result |
  |---|---|
  | on a connection whose first request was challenged | 16/16 x 403, ~740 ms each |
  | on a connection that once returned 200 | 24/24 x 200, 28-116 ms, *any* variant |

  Every 403 carries `cf-mitigated=challenge` **and `Connection: close`** — the challenge
  kills the connection, so the retry necessarily opens a fresh one and draws a fresh
  verdict. Every 200 carries `keep-alive`, and that connection then serves everything
  put on it. Adding browser-shaped image headers (`Accept`, `Referer`, `sec-fetch-*`)
  or dropping the cross-host `__cf_bm` changed *nothing*: variants A-D were
  indistinguishable on both sides of that table. The retry loop is load-bearing, but
  what it is really sampling is connections.

  This is what makes the failures front-loaded rather than load-accumulated. On a cold
  launch the pool is empty and six workers each open a cold connection; on the 13:21
  baseline the first five requests all 403'd while the sustained middle stretch at full
  rate was clean, and `a.furaffinity.net` — only four avatars, so it never got a warm
  connection — went 20/20 x 403 against `t.furaffinity.net`'s 30 of 135 responses.
  Getting more requests onto warm connections is therefore the lever — but the obvious
  way to pull it does not work. **HTTP/2 was measured and rejected.** It looked ideal
  (FA's CDN offers it; it multiplexes a burst onto one connection instead of h1's one
  per concurrent request; it is what iOS gets for free, since URLSession always
  negotiates h2 and cannot be told not to — verified with `URLSessionTaskMetrics`:
  `proto=h2`, one connection per host, everything after the first reusing it). Ten
  cold-launch runs on one emulator session, five per protocol:

  | | responses | 403 rate | images never loaded | fully clean runs |
  |---|---|---|---|---|
  | h2 | 444 | 12% | 7 | 3 / 5 |
  | h1 | 463 | 15% | 6 | 1 / 5 |

  A wash on the numbers, and worse where it counts: h2's single connection is a single
  point of failure, so one bad draw loses *every* avatar at once (one run lost 7 of 8),
  where h1's six draws decorrelate and the retries recover. Note also how wide the
  run-to-run spread is even within one session — 0% to 97% on the same host — so never
  judge a change here on one run.
- **The retry backoff sleeps inside `FAImageStore`'s concurrency permit, and that is
  load-bearing.** It looks like pure waste: `FACoilBridge.fetchResult` runs all five
  attempts inside one JNI call, so up to 2.5 s of `Thread.sleep` holds 1 of the gate's
  6 permits while doing nothing, and five other images wait behind it. Moving the loop
  into Swift so the permit is re-acquired per attempt and the backoff runs outside it
  makes things dramatically **worse**. Cold runs on one emulator session, A-B-A so the
  session's own drift is visible:

  | arm | runs | responses/run | 403 rate | images lost/run | issuance span | drain |
  |---|---|---|---|---|---|---|
  | A1 backoff inside the permit | 9 | 122 | 29% | 2.8 | 7.1 s | 8.8 s |
  | B1 backoff outside it | 9 | 221 | **75%** | **25.4** | — | 3.3 s |
  | B2 as B1, but ≤6 URLs retrying at once | 9 | 150 | 48% | 1.7 | 2.0 s | 8.6 s |
  | A2 backoff inside the permit, again | 6 | 106 | 26% | 1.0 | 4.2 s | 5.0 s |

  The permit is not just a concurrency bound, it is the **pacing**. Holding it across
  the backoff caps the burst at six URLs in the retry cycle; freeing it let all ~80
  URLs of a cold launch retry in lockstep — every one exhausting all five attempts,
  ~400 connection attempts in 3.4 s — and Cloudflare answers a burst like that by
  challenging everything (B1 lost 64, 75 and 81 images on single runs; A1's worst was
  6). Capping retry concurrency (B2) recovers most of that, but note A1 → B2 → A2 in
  chronological order: images lost/run falls 2.8 → 1.7 → 1.0 monotonically, which is
  the session drifting, not the change working. B2 buys faster *issuance* (2.0 s vs
  4-7 s) and nothing else, at 40% more requests against FA's CDN. Reverted; the Kotlin
  loop stays.

  Corollary for the summarizer: `[Coil] GET request on` must be logged from **inside**
  the permit. Logged before it, the line marks when a `Task` was created rather than
  when the request went out, and `summarize-image-log.py`'s issuance cadence silently
  becomes meaningless (every gap 0 ms).
- **A scroll test measures nothing on the Followed feed.** Its whole 72-item page is
  prefetched during the cold burst, so scrolling through it serves every thumbnail from
  disk: the feed position advances and the `[Coil]` GET count does not move. Anything
  that needs a *second* burst in the same process (connection-pool behaviour, say) has
  to trigger one another way — clearing the caches from Settings and pulling to refresh
  is the one that also drops the memory LRU, which otherwise absorbs everything.
- **The Kotlin bridges' `android.util.Log` output never reaches the log file Settings
  exports**, which only carries what went through the Swift `logger`
  (`PersistentLogger`). So anything worth keeping has to be *returned* to Swift and
  logged there — the reason `FACoilBridge.fetch` became `fetchResult`, handing back
  `{path, attempts, bytes, ms, failures}` as JSON so `CoilImageLoader.fetchPath` can
  emit the one `[Coil] GET request on <url>` line per network fetch (the analog of
  iOS's `[KF]` line) plus a retry/failure line. The same applies to the other bridges.

Measured on the emulator before/after this work — cold, disk cache wiped, time for the
first visible thumbnail to appear:

| | before | after |
|---|---|---|
| first visible thumbnail | 4783 ms | 342 ms |
| per-URL network fetch (p50) | 48 ms | 48 ms |
| requests per feed page | 148 | 84 |
| thumbnail prefetches actually used | 0 / 72 | 72 / 72 |

The network was never the problem: the visible rows were queued behind ~144 unbounded
prefetches. Scrolling 72 items and back now serves 93 images from memory vs 38 re-decodes.
