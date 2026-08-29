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
- **Retry only what a fresh connection could answer differently** (`worthRedrawing`).
  The loop exists for Cloudflare's per-connection verdict, so a 4xx that is the origin's
  own answer gets one attempt, not five. FA answers a **404** for a user with no custom
  avatar — while still serving its default image — so those five attempts were five
  requests plus ~2.5 s of backoff per missing avatar, each of them holding one of
  `FAImageStore`'s six permits. 403 (the verdict itself), 408 and 429 keep their
  retries, as does anything that is not an HTTP status.
- **The width passed to `prefetchingPreviews` must be the width the row renders at.**
  `bestThumbnailUrl(for:)` snaps to discrete buckets, so a few dp of difference changes
  the URL and silently voids every prefetch. This is what the `listRowInsets` fork is for.
- **Cloudflare's verdict on an image request is per *connection*, not per request and
  not per header set.** Measured on the emulator with a debug-only header probe in
  `FACoilBridge` — a 4 URL x 5 variant Latin square run inside one launch, so that
  run-to-run drift could not be mistaken for an effect (removed once the connection
  instrument below superseded it; `git log -- Android/app/src/main/kotlin` has it):

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
- **The connection is measured, not inferred.** All of the above was read off 403
  patterns until `FACoilBridge` grew an `EventListener.Factory` reporting, per attempt,
  which connection carried it (`conn=`) and whether that attempt opened it (`new=`).
  `summarize-image-log.py` splits the 403 rate on it. Eight cold runs settle the model:

  | | responses | 403s |
  |---|---|---|
  | rode a connection this request opened | ~140 | 21-96% per run, median 73% |
  | rode a connection already in the pool | ~600 | **0** |

  Not one 403 on a reused connection, in any run. Two traps if you touch this
  instrument: `connectStart` fires on OkHttp 5's own fast-fallback connect threads, so
  a listener that resolves a `ThreadLocal` *inside* the callback reports `new=false`
  for every request of a cold launch — bind the state in `create(call)`, which does run
  on the caller's thread. And `conn` is `System.identityHashCode`, so it is only
  meaningful within one process.
- **Getting more requests onto warm connections is the lever, and the two obvious ways
  to pull it have both been measured and rejected.** Twice, in the case of HTTP/2.

  **HTTP/2 alone.** It looked ideal (FA's CDN offers it; it multiplexes a burst onto
  one connection instead of h1's one per concurrent request; it is what iOS gets for
  free, since URLSession always negotiates h2 and cannot be told not to — verified with
  `URLSessionTaskMetrics`: `proto=h2`, one connection per host, everything after the
  first reusing it). Ten cold-launch runs on one emulator session, five per protocol:

  | | responses | 403 rate | images never loaded | fully clean runs |
  |---|---|---|---|---|
  | h2 | 444 | 12% | 7 | 3 / 5 |
  | h1 | 463 | 15% | 6 | 1 / 5 |

  A wash on the numbers, and worse where it counts: h2's single connection is a single
  point of failure, so one bad draw loses *every* avatar at once (one run lost 7 of 8),
  where h1's six draws decorrelate and the retries recover.

  **A launch ramp** — admit one cold connection per host at a time, widen +1 per
  network success up to the existing limit of 6 — is what the per-connection model
  argues for directly: six simultaneous workers are six independent bad draws, so draw
  serially and widen only on proof. It works mechanically. Its draws do go serial
  (`0.0 1.3 1.6 1.8 1.9 2.8 2.9 4.2 s` against a baseline's `0.0 0.0 0.0 0.4 0.5 1.4`)
  and it still loses. A-B-A, 8 cold runs per arm:

  | arm | 403% | images lost | connections | drain |
  |---|---|---|---|---|
  | A1 shipping | 14% | 0.0 | 17.5 | 3.1 s |
  | B ramp | 16% | 1.0 | 21.5 | 4.7 s |
  | A2 shipping | 8% | 0.0 | 14.0 | 2.5 s |

  Connections opened was its primary criterion and went *up*. Serialising the draws
  stretches the burst from ~2 s to ~4-9 s, and a host that never draws a good
  connection never widens — so it pays one ~3.5 s retry cycle per URL, where the
  baseline's six simultaneous draws need only *one* winner before ~70 requests ride it.

  **The ramp on HTTP/2**, which is the pairing the two failures seem to argue for — h2
  lacks any way to re-draw, the ramp is exactly that selection — fails for a structural
  reason worth remembering: **under h2 the ramp has nothing to select.** Widening a
  host limit opens no second connection, because h2 multiplexes onto the one it has.
  There is only ever a single draw.

  | arm | 403% | images lost | connections | drain |
  |---|---|---|---|---|
  | A1 shipping (h1, no ramp) | 2% | 0.0 | 12.0 | 1.9 s |
  | B h2 + ramp | 51% | **11.0** | 2.0 | **20.1 s** |
  | C h2 + ramp + eviction | 16% | 2.0 | 10.5 | 6.1 s |
  | A2 shipping (h1, no ramp) | 11% | 0.0 | 21.0 | 2.6 s |

  Arm B is the interesting one, and the instrument names it exactly: 2 connections,
  **100% 403 on new *and* on reused**. Under h1 a challenge carries `Connection: close`
  and the connection dies with it, so a retry necessarily draws fresh — the whole
  reason the per-connection model reads as cleanly as it does. **h2 has no such
  header.** All five attempts ride the same connection, the ramp never widens because
  it never sees a success, and every URL serialises through its own 5-attempt cycle:
  four of eight runs loaded all 72 feed items and then lost every image, over 40+ s.
  Evicting the challenged connection (`connectionPool.evictAll()`, arm C) removes the
  collapse and is still beaten by both shipping arms on every count.

  Two things worth keeping out of it. **h2 coalesces `a.` and `t.` onto one
  connection** — the same `conn=` id serves both hosts — which does structurally fix
  `a.furaffinity.net` never accumulating enough traffic to warm one; it just is not
  worth what a single point of failure costs. And note how wide the run-to-run spread
  is even within one session — 0% to 99% on the same host, strongly bimodal — so never
  judge a change here on one run, and read each arm's *worst* run next to its median
  (`compare-image-runs.py` prints both). The medians describe the good mode only.
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
- **Measure with `Scripts/Android/cold-image-run.sh`, one run at a time.** It holds the
  shared-emulator lock for its whole duration, because a background loop colliding with
  a manual launch has already produced one wrong conclusion here. Then
  `compare-image-runs.py --arm A1 … --arm B … --arm A2 …` for the tables above. Two
  rules that were learnt the expensive way: a run is discarded only when the **feed
  page** never loaded (`prefetchThumbnails count=`), never on a low image-GET count —
  a collapsed image layer issues few requests too, and that rule would have thrown away
  the four worst runs of the h2 arm. And nothing else may issue image requests during
  a run — the header probe had to be disarmed for exactly this reason before it was
  removed, since its 20 blocking requests went through the *shared* client and landed
  in the connection counter.
- **A scroll test measures nothing on the Followed feed.** Its whole 72-item page is
  prefetched during the cold burst, so scrolling through it serves every thumbnail from
  disk: the feed position advances and the `[Coil]` GET count does not move. Anything
  that needs a *second* burst in the same process (connection-pool behaviour, say) has
  to trigger one another way — clearing the caches from Settings and pulling to refresh
  is the one that also drops the memory LRU, which otherwise absorbs everything.
- **The disk cache's two limits come from two places.** coil3's `DiskCache` *requires*
  a maximum size — `DiskCache.Builder` defaults to `maxSizePercent(0.02)` — and offers
  no expiry whatsoever, so the ceiling is coil's constraint and the lifetime is ours.
  iOS is the exact mirror image: Kingfisher's `sizeLimit` is left at its unbounded
  default `0`, and only the 7-14 day expiry bites. So `FACoilBridge` sets **1 GB** and
  applies a **7-14 day** per-entry lifetime lazily, in `cachedPath` — the one door both
  `fetchResult` and `isCached` come through, so an expired entry is dropped and
  re-downloaded with no second implementation and the feed's cache reporting stays
  honest. The window is measured from the *write*: coil never touches mtime on a read,
  and iOS deliberately doesn't extend on access either
  (`.diskCacheAccessExtending(.none)`). The spread within it is
  `url.hashCode() % 8` days rather than random, so a deadline survives a process
  restart while a cache filled in one session still doesn't expire in one go — Kotlin's
  `String.hashCode` is specified, unlike Swift's per-process-seeded one.
  `FAImageStore.pruneStagedMedia` already covers the `fa-media` staging directory at
  7 days.
- **The Kotlin bridges' `android.util.Log` output never reaches the log file Settings
  exports**, which only carries what went through the Swift `logger`
  (`PersistentLogger`). So anything worth keeping has to be *returned* to Swift and
  logged there — the reason `FACoilBridge.fetch` became `fetchResult`, handing back
  `{path, attempts, bytes, ms, failures}` as JSON so `CoilImageLoader.fetchPath` can
  emit the one `[Coil] GET request on <url>` line per network fetch (the analog of
  iOS's `[KF]` line) plus a retry/failure line. The same applies to the other bridges.
- **`SubmissionFeedItemView.controlCacheBehavior` reports from the *feed card's* point
  of view**, which the `[Coil]` lines cannot: on each row appearance it says whether
  that thumbnail is already in flight (and for how long) or neither cached nor
  starting. It is shared with iOS — `FAImageStore.downloadStartDate(for:)` and
  `isCached(_:)` stand in for `DownloadDelegate.downloadStartDate(for:)` and
  Kingfisher's `imageCachedType`. A warm feed logs neither line, so clear the caches
  from Settings and pull to refresh to see it work.

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
