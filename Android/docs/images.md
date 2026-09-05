# Images

Kingfisher runs on Android too (see [forks.md § Why Kingfisher is
forked](forks.md#why-kingfisher-is-forked)), so the memory cache, the disk cache, the
expiry policy, the processor, `KFImage` and `ImagePrefetcher` are the same code on both
platforms. **Coalescing is not**, though it reads like it should be: Kingfisher dedupes
concurrent loads for a URL inside `SessionDataTask`/`SessionDelegate`, which a
downloader that replaces the transport never reaches — so the download is coalesced by
`FAImageStore.bytes(for:)` and the decode by `DecodeCoalescer`, both Android-only. What
else stays Android-only is the *transport* underneath it, because Cloudflare judges a
connection and pages and images must share one pool:

```
FAHttpClient.kt        the app's ONE OkHttpClient and ONE ConnectionPool, shared with
                       the page path (FAHttpBridge). Credentials, the connection
                       instrument, and the epoch-guarded eviction live here.
FACoilBridge.kt        the image retry loop. Stages a fetch in a throwaway file under
                       cacheDir and returns its PATH — it caches nothing.
CoilImageLoader.swift  AnyDynamicObject/JNI driver for it; reads that file and unlinks
                       it. The `[Coil]` log prefix and the file names are kept because
                       `summarize-image-log.py` counts them and the measured runs below
                       are stated in them.
FAImageStore.swift     what is left: the two-FIFO concurrency gate, the challenge park,
                       the connection-pool epoch, and fetch coalescing.
FAKingfisherDownloader
  +Android.swift       `FAOkHttpDownloader`, an `ImageDownloader` subclass that
                       overrides the single method `KingfisherManager` calls. Kingfisher's
                       own URLSession is never used here. `DecodeCoalescer` lives here
                       too, keyed by URL *and* processor identifier.
```

One client is the premise, not a tidiness choice: Cloudflare judges a connection, so
the fewer the app opens the fewer independent verdicts it draws, and a challenge on
the one it has is *repairable* rather than a lost draw. See
[cloudflare-and-login.md § Repairing a challenge](cloudflare-and-login.md#repairing-a-challenge-measured-2026-09-01).

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
- **The memory cache needs an explicit ceiling here.**
  `ImageCache.createMemoryStorage()` sizes itself at `ProcessInfo.processInfo.physicalMemory / 4`,
  which is no bound at all on Android: `NSCache.totalCostLimit == 0` means *unlimited*,
  so a `physicalMemory` the Android SDK's Foundation reports as 0 leaves the cache
  unbounded rather than merely large. And `MemoryStorage.Backend`'s `cleanTimer` is a
  `Timer.scheduledTimer`, which never fires without a running run loop — so the cost
  limit is the *only* thing bounding it. `configureImageCacheForAndroid()`, called from
  `FurAffinityUIRoot.onInit`, sets it to 64 MB: what `FAImageMemoryCache` carried before
  the move to Kingfisher, so the runs below stay comparable. iOS is untouched, where
  NSCache purges under system memory pressure and corelibs' does not.
- **Settings counts and clears `fa-media` as well as the disk cache.**
  `ImageCacheControl.formattedDiskSize()` adds `mediaCopiesDiskSize()` and `clear()`
  calls `clearMediaCopies()`, because under-reporting would make the row's number
  disagree with what clearing actually reclaims. Both are blocking file I/O and go
  through `FAImageStore.performingFileIO`, the same gate the fetch and the decode use —
  as does the `onStop` sweep, which used to be a `Task.detached` onto the cooperative
  pool. iOS counts only Kingfisher's cache: `tmp/` there is the system's to purge.
- **Never block on a cooperative-pool thread.** FurAffinityUI is a *native* Skip module,
  so a blocking JNI call there pins a thread Swift concurrency owns. Both blocking calls
  in this pipeline — the fetch and the decode — go through `FAImageStore`'s gate, which
  submits to a real `DispatchQueue`. The decode is easy to lose: `FAOkHttpDownloader`
  runs in a plain `Task`, so `options.processor.process(...)` would otherwise decode
  wherever that task resumed.
- **No image bytes cross JNI.** The bridge returns a path; Swift reads that file
  natively and unlinks it.
- **A challenge is reported, not retried into.** `FACoilBridge` hands
  `cf-mitigated: challenge` back to Swift — under h1 once its five attempts are spent,
  since each of those genuinely redials, and immediately otherwise. `FAImageStore` then
  parks on `awaitResolution()` and retries once on the repaired pool, which is how an
  image that drew a bad verdict stops being simply lost.
- **Park inside the permit.** The measured catastrophe (75% 403, 25 images lost per run)
  was freeing the permit across the wait and letting ~80 URLs resume in lockstep. Holding
  it caps parked fetches at six and leaves the rest in the gate's FIFO, off the network
  entirely; on release they retry and hand their permits on one at a time. The park is
  capped at 20 s — a failed page fetch is visible, six permanently parked permits would
  freeze the image layer silently. Nothing on the resolution path takes a permit, which
  is why this cannot deadlock; the argument is in the comment because a future change
  could break it.
- **A lost image has to say so in the shape the summariser counts.** A challenged fetch
  exits early, so it logs no `failed after …` line of its own; `FAImageStore` emits one
  when it finally gives up. The same hole reopened on a second path — a 200 whose staged
  file could not be read back — which returned `.failed` with only an `[Coil] … staged
  bytes unreadable` line; it goes through `logAbandoned` too. Without such a line a
  challenged image that never came back looks exactly like one that was never asked
  for — and "images lost" is the number every arm here is judged on. Cost of learning that: one h2 arm that read as 0% 403 and 0 images
  lost while it was actually losing every image it attempted.
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

  **h2 with a coordinator-driven repair** — the one arm none of the above tested, and
  the reason for all of `FAHttpClient`: evict, solve the challenge in the WebView, mint
  a fresh clearance, redial. It is measured in the next section, and it loses too.

## HTTP/2, for the third and last time (measured 2026-09-01)

The two earlier h2 arms both retried blindly with a dead clearance. This one repairs:
one shared client for pages *and* images, evictions guarded by an epoch, and
`awaitResolution()` on the first challenge. A-B-A, **8 cold runs per arm**, protocol
switched by a prefs file so nothing is rebuilt between arms and the run asserts the arm
it actually got.

Everything h2 promised, it delivered:

| | image 403% | distinct connections | connections serving >1 host |
|---|---|---|---|
| MEDIAN h1 / **h2** / h1 | 7% / **0%** / 19% | 21 / **2.5** / 32 | 0 / **1** / 0 |
| WORST h1 / **h2** / h1 | 39% / **0%** / 29% | 51 / **5** / 64 | 0 / **1** / 0 |

`www.` **does** coalesce with `t.` and `a.` — structurally predicted, never previously
measured, and now direct:

```
h2=true   census cold pool=1 idle=1 conns=1  calls=85
          census conn=88501491 calls=85 hosts=a.,t.,www.furaffinity.net
h2=false  census cold pool=5 idle=5 conns=43 calls=118
          census conn=92260943 calls=38 hosts=t.furaffinity.net   …42 more, one host each
```

One connection carried the entire cold launch. (Those `census` lines came from a
per-connection tally built to answer exactly this question; it was retired with the
switch, since under the h1 that ships it can only ever print one host per connection.
The per-request `conn=`/`new=` tokens, which `summarize-image-log.py` builds its
connection table from, say the same thing at higher resolution.)

And it still does not ship, for one reason: **the repair cannot repair it.**

| | images lost per run |
|---|---|
| h1 A1, 8 runs | 0 0 0 0 0 0 3 1 |
| **h2 B, 8 runs** | 0 0 0 0 0 **14 28 35** |
| h1 A2, 8 runs | 0 0 0 0 0 0 2 5 |

Post-repair retries that came back 200: **0 of 26** in the worst h2 run, against 100%
once the page path had a pool to evict under h1. Forced-challenge runs say the same
thing louder — three per arm, and the one h2 run that drew a bad verdict produced 328
page 403s, 61 challenged URLs, **40** separate resolutions and 58 lost images, where
the worst h1 run in the same session lost 2.

The mechanism is the one the ramp arm already named, now with the repair ruled out as
a fix: under h2 there is exactly **one** connection, so a bad verdict poisons every
request at once, and evicting it and redialling draws the *same* verdict again. h1's
20-60 connections are 20-60 independent draws, and one winner carries ~70 requests.
Cloudflare is not deciding per connection so much as per *client-and-moment*, and h1
simply resamples that moment more often.

So the model behind `Android/docs/images.md` survives intact, and the conclusion is
sharper than before: **the number of connections is not the thing to minimise.** Being
able to redraw is.

The protocol is therefore pinned to h1 in `FAHttpClient.shared()`: re-measuring h2 means
editing that one `.protocols(…)` line and rebuilding, which is how both h2 arms above
were run. Everything else the work built for it is kept, because all of it pays under
h1: the shared client, the epoch guard, and the repair.

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

  The backoff inside that permit is a **flat 1 s**, not the `250 ms x attempt` ramp it
  started as, and 1 s because that is what `www.furaffinity.net`'s `robots.txt` asks a
  crawler to wait. The directive does not formally bind this code — it is aimed at
  crawlers, and `d.`/`t.`/`a.furaffinity.net` serve no `robots.txt` at all (404), while
  the app already honours it where it genuinely crawls
  (`ProgressiveLoadItem.crawlingDelay = 1 s`) — but nothing here should hit an FA host
  faster than that either. Worst case, one URL holds its permit for 4 s instead of 2.5 s.
  Since the pacing is load-bearing (above), it was measured A-B-A rather than assumed —
  6 cold runs per arm, one emulator session:

  | arm | 403% | images lost (median / worst) | conns | issuance | drain |
  |---|---|---|---|---|---|
  | A1 `250 ms x attempt` | 22% | 0.0 / 2 | 28.5 | 3.5 s | 4.8 s |
  | B flat 1 s | 6% | 0.0 / 6 | 16.5 | 2.7 s | 2.9 s |
  | A2 `250 ms x attempt`, again | 5% | 0.0 / 9 | 15.0 | 1.9 s | 3.5 s |

  B lands *between* the two shipping arms on every column, and the shipping arms
  themselves move 22% → 5% across the session — so what the table shows is drift, not
  an effect, in either direction. Same story on the worst runs: 2 → 6 → 9 images lost is
  monotone in chronological order. No measurable regression, so the slower, politer
  backoff stays.

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
- **The disk cache is Kingfisher's, and so is its policy.** There used to be two — a
  coil3 `DiskCache` under the transport and Kingfisher's above it — which meant every
  image was written twice and the 7-14 day expiry existed in two implementations, one of
  them Kotlin's (coil's `DiskCache` *requires* a size ceiling and offers no expiry at
  all, so the two halves sat on opposite sides of JNI). Now `FACoilBridge` stages a fetch
  in a throwaway file and Kingfisher stores the only copy, under
  `cache/com.onevcat.Kingfisher.ImageCache.default`, with the same
  `.diskCacheExpiration(.days(7...14))` / `.diskCacheAccessExtending(.none)` iOS has.
  The sweep is `UIApplicationDidEnterBackground` on iOS and `onStop` here, since
  `ImageCache` cannot observe Android's lifecycle. Settings reports and clears that one
  number.
- **`temporaryDirectory` is not temporary here.** `cachedImageFileURL` copies out of the
  disk cache so Save/Share hands over a file with a real name and extension, and on iOS
  those land in `tmp/`, which the system purges. On Android `temporaryDirectory` resolves
  to the app's `cacheDir`, which nothing empties short of storage pressure — so every
  submission ever opened left a full-resolution file behind. The copies go in
  `tmp/fa-media/<UUID>/<remote filename>` and `onStop` prunes them at a day. Three
  details of that path are load-bearing. The copy is only staged when
  `allowZoomableSheet` is set, since nothing else reads it — `SubmissionPreviewView`
  (`RemoteSubmissionView`'s placeholder), the story cover and the audio cover all pass
  `false` and bind `fullResolutionMediaFileUrl` to a constant. The UUID is the
  *directory*, not a filename prefix, because `MediaBridge` hands `lastPathComponent` to
  MediaStore as the gallery entry's display name and to the share sheet, and neither
  call site has the remote URL to pass a better one from. And the name still goes
  through `FAFileStaging.safeFileName`: a remote filename is attacker-controlled and
  `lastPathComponent` percent-decodes, so one carrying a separator fails `copyItem`
  outright and the submission silently loses both its zoom viewer and Save/Share.
- **The Kotlin bridges' `android.util.Log` output never reaches the log file Settings
  exports**, which only carries what went through the Swift `logger`
  (`PersistentLogger`). So anything worth keeping has to be *returned* to Swift and
  logged there — the reason `FACoilBridge.fetch` became `fetchResult`, handing back
  `{path, attempts, bytes, ms, failures}` as JSON so `CoilImageLoader.fetchImageData`
  can emit the one `[Coil] GET request on <url>` line per network fetch plus a
  retry/failure line. The same applies to the other bridges. The `[Coil]` prefix is kept
  now that coil is gone: `summarize-image-log.py` counts it, and every measurement on
  this page is stated in it.
- **`SubmissionFeedItemView.controlCacheBehavior` reports from the *feed card's* point
  of view**, which the `[Coil]` lines cannot: on each row appearance it says whether
  that thumbnail is already in flight (and for how long) or neither cached nor
  starting. It is one implementation on both platforms now, over
  `DownloadDelegate.downloadStartDate(for:)` and `ImageCache.imageCachedType` —
  `FAOkHttpDownloader` calls the same delegate hooks the URLSession downloader does. A
  warm feed logs neither line, so clear the caches from Settings and pull to refresh to
  see it work.

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

## Moving to Kingfisher (measured 2026-09-05)

A-B-A, cold runs on one emulator session, against the port that preceded it — the same
tree at `2c31fe2`, installed side by side as its own app so neither arm needed a
reinstall or a fresh login between runs (the app id carries the worktree name, so a
second worktree is a second app with its own container; that is the way to run an A-B-A
that needs two builds).

| arm | runs | 403% median / worst | images lost median / worst | connections median | drain median |
|---|---|---|---|---|---|
| A1 shipping | 7 | 15% / 46% | 0.0 / **5.0** | 23 | 15.1 s |
| B Kingfisher | 8 | **0% / 4%** | **0.0 / 0.0** | 13 | 3.9 s |
| A2 shipping | 8 | 0% / 36% | 0.0 / **3.0** | 17 | 3.8 s |

Read the worst run, not the median — the spread here is bimodal and B's advantage is
entirely in it: **no B run lost an image**, where each shipping arm had one run that lost
several. Time from the first image GET to the first `t.furaffinity.net` 200, which is
what a user sees fill in:

| arm | median | worst |
|---|---|---|
| A1 shipping | 1558 ms | 11064 ms |
| B Kingfisher | **542 ms** | **1017 ms** |
| A2 shipping | 660 ms | 2045 ms |

Two caveats on the arms themselves. A1 has seven runs, not eight: the emulator degraded
mid-arm (autologin's hidden WebView stopped finishing inside the 50 s window) and was
rebooted with 4096 MB before B, so **A2 is the arm B should be read against** — it is the
one measured under the same conditions. And B is not obviously *causing* the improvement:
the transport is unchanged, so the honest claim is that replacing the cache and view
layers costs nothing measurable and does not regress the number this pipeline is judged
on.

### The review fixes on top of it (measured 2026-09-05)

The memory cap and the decode coalescer above are the two of those fixes that touch
image-layer behaviour, so they were measured the same way. A-B-A, 8 cold runs per arm,
one emulator session, B installed between the two shipping arms:

| arm | 403% median / worst | images lost median / worst | conns median | drain median |
|---|---|---|---|---|
| A1 before | 16% / 45% | 0.0 / 3.0 | 32.0 | 11.2 s |
| B cap + decode coalescing | 22% / 53% | 0.0 / 10.0 | 34.5 | **11.1 s** |
| A2 before, again | 28% / 35% | 0.0 / 6.0 | 40.5 | 16.6 s |

B lands *between* the two shipping arms on every median column, and the shipping arms
themselves move 16% → 28% and 11.2 s → 16.6 s across the session — so what the table
shows is the session drifting, in the direction it always drifts, not an effect. Read
the worst runs the same way: 3 → 10 → 6 images lost is noisy in both directions, and
none of the three arms has a median above 0. Neither change issues a request, so
there is no mechanism by which either could move a 403 rate; the reason to measure was
that the cap trades memory-cache hit rate for a bounded footprint, and the drain
column says that costs nothing on a cold burst.
