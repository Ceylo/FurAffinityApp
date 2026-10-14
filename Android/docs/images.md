# Images

Kingfisher runs on Android too (see [forks.md § Why Kingfisher is
forked](forks.md#why-kingfisher-is-forked)), so the memory cache, the disk cache, the
expiry policy, the processor, `KFImage` and `ImagePrefetcher` are the same code on both
platforms. **Coalescing is not**: Kingfisher dedupes concurrent loads inside
`SessionDataTask`/`SessionDelegate`, which a downloader that replaces the transport
never reaches, so `FAImageStore.bytes(for:)` and an `InFlightCoalescer` do it here. What
else stays Android-only is the *transport* underneath, because Cloudflare judges a
connection and pages and images must share one pool:

```
FAHttpClient.kt        the app's ONE OkHttpClient and ONE ConnectionPool, shared with
                       the page path (FAHttpBridge). Credentials, the connection
                       instrument, and the epoch-guarded eviction live here.
FAImageFetchBridge.kt  the image retry loop. Stages a fetch in a throwaway file under
                       cacheDir and returns its PATH — it caches nothing.
ImageFetchBridge.swift AnyDynamicObject/JNI driver for it; reads that file and unlinks
                       it, and emits the `[IMG]` lines.
FAImageStore.swift     what is left: the two-FIFO concurrency gate, the challenge park,
                       the connection-pool epoch, and fetch coalescing.
FAKingfisherDownloader
  +Android.swift       `FAOkHttpDownloader`, an `ImageDownloader` subclass that
                       overrides the single method `KingfisherManager` calls. Kingfisher's
                       own URLSession is never used here. The decode `InFlightCoalescer`
                       too, keyed by URL *and* processor identifier.
```

One client is the premise, not a tidiness choice: Cloudflare judges a connection, so
a challenge on the one the app has is *repairable* rather than a lost draw. See
[cloudflare-and-login.md § Repairing a challenge](cloudflare-and-login.md#repairing-a-challenge-measured-2026-09-01).

## Rules

- **Never push a `Cookie:` header that lost its `cf_clearance`.** The image layer
  cannot pull a fresh header per request, so `FAWebSession.refreshedCookieHeader()`
  keeps the two in step — and a header read *mid-wipe* has no clearance. Pushing it
  de-seeds every later request and turns one challenge into a stampede. So if the
  incoming header has no clearance and the last pushed one did, keep the last one:
  expiring a cookie locally does not invalidate it at the edge. The check,
  `String.carriesCloudflareClearance` (FAKit, tested in `StringFATests`), matches the
  cookie *name*, so `xcf_clearance` doesn't count.
- **The memory cache needs an explicit ceiling.** Kingfisher's default,
  `physicalMemory / 4`, bounds nothing here: a `totalCostLimit` of 0 means unlimited,
  and `MemoryStorage`'s `cleanTimer` never fires without a run loop.
  `configureImageCacheForAndroid()` sets 64 MB. iOS purges under memory pressure.
- **`alsoPrefetchToMemory` stays off.** `prefetchThumbnails` prefetches the whole
  48-item page, so promoting it would decode 48 `@600` bitmaps of ~1 MB each into the
  64 MB cache and evict the rows on screen. The cost is one frame on a thumbnail's first
  appearance after a cold launch onto a warm disk.
- **Settings counts and clears `fa-media` as well as the disk cache**, or the row's
  number disagrees with what clearing reclaims. Both halves, and the `onStop` sweep, are
  blocking file I/O and go through `FAImageStore.performingFileIO`.
- **Never block on a cooperative-pool thread.** FurAffinityUI is a native Skip module,
  so a blocking JNI call there pins a thread Swift concurrency owns. The fetch *and* the
  decode go through `FAImageStore`'s gate, a real `DispatchQueue`. The decode is the easy
  one to lose: `FAOkHttpDownloader` runs in a plain `Task`.
- **Download progress is pushed, and throttled in Kotlin.** `FAImageFetchBridge`'s copy
  loop calls the bridged `FAImageFetchProgressSink` at most every 100 ms, and only once a
  copy has run that long, so thumbnails push nothing. The sink fans out to
  `ImageFetchBridge.progressUpdates(for:)`, which `FAOkHttpDownloader` subscribes to
  *before* awaiting the bytes and forwards to `reportDownloadProgress`, which feeds
  `SubmissionMainImage`'s bar. Measured against the poller it replaced: 0 images lost in
  every arm.
- **No image bytes cross JNI.** The bridge returns a path; Swift reads that file and
  unlinks it.
- **A challenge is reported, not retried into.** `FAImageFetchBridge` hands
  `cf-mitigated: challenge` back to Swift once its five attempts are spent. `FAImageStore`
  parks on `awaitResolution()` and retries once on the repaired pool.
- **Park inside the permit.** Freeing the permit across the wait let ~80 URLs resume in
  lockstep: 75% 403, 25 images lost per run. Holding it caps parked fetches at six and
  leaves the rest off the network in the gate's FIFO. The park is capped at 20 s, and
  nothing on the resolution path takes a permit, so it cannot deadlock (the argument is
  in the code comment).
- **The retry backoff sleeps inside the permit, too.** It looks like waste — up to 4 s
  holding 1 of 6 permits — but the permit is the *pacing*. Moving the backoff outside it
  took a cold launch from 29% to **75%** 403 and from 2.8 to **25.4** images lost per run;
  capping concurrent retries instead bought nothing beyond session drift. The backoff is
  a flat 1 s, what `www.furaffinity.net`'s `robots.txt` asks of a crawler; measured
  against the old `250 ms × attempt` ramp, the difference was within drift. None of this
  loop has an iOS counterpart: URLSession keeps one warm h2 connection per host, and no
  reused connection was ever challenged.
- **A lost image has to say so.** A challenged fetch exits early and logs no `failed
  after …` line of its own, so `FAImageStore` emits one when it gives up, as does a 200
  whose staged file could not be read. Without it a lost image looks like one never asked
  for — one h2 arm read as 0 images lost while it lost every image it tried.
- **`[IMG] GET request on` is logged from inside the permit**, so it dates the request
  going out, not the `Task` being created.
- **Retry only what a fresh connection could answer differently** (`worthRedrawing`).
  FA answers **404** for a user without a custom avatar, which used to cost five requests
  and ~4 s of a permit each. 403, 408, 429 and non-HTTP failures keep their retries.
- **The width passed to `prefetchingPreviews` must be the width the row renders at.**
  `bestThumbnailUrl(for:)` snaps to buckets, so a few dp change the URL and void every
  prefetch. This is what the `listRowInsets` fork is for.
- **The disk cache is Kingfisher's, and so is its policy**: one copy under
  `cache/com.onevcat.Kingfisher.ImageCache.default`, with iOS's
  `.diskCacheExpiration(.days(7...14))` / `.diskCacheAccessExtending(.none)`. The sweep
  runs on `onStop`, since `ImageCache` cannot observe Android's lifecycle.
- **`temporaryDirectory` is not temporary here** — it is `cacheDir`, which nothing
  empties. Save/Share copies go in `tmp/fa-media/<UUID>/<remote filename>`, and `onStop`
  prunes them at a day. They are staged only when `allowZoomableSheet` is set; the UUID
  is the directory, not a prefix, because `MediaBridge` uses `lastPathComponent` as the
  gallery and share name; and the name goes through `FAFileStaging.safeFileName`, since
  `lastPathComponent` percent-decodes and a separator in it fails `copyItem`.
- **`android.util.Log` never reaches the log file Settings exports.** Anything worth
  keeping is *returned* to Swift and logged there — why `fetchResult` hands back
  `{path, attempts, bytes, ms, failures}` as JSON. The same holds for every bridge.
- **`SubmissionFeedItemView.controlCacheBehavior` reports from the feed card's point of
  view**: whether a row's thumbnail is already in flight, or neither cached nor
  starting. A warm feed logs neither line; clear the caches from Settings and pull to
  refresh to see it.
- **A scroll test measures nothing on the Followed feed.** The whole page is prefetched
  during the cold burst. Clearing the caches from Settings and pulling to refresh is the
  way to get a second burst in one process.

## Cloudflare judges a connection

Every image 403 carries `cf-mitigated=challenge` **and `Connection: close`**; every 200
carries `keep-alive`, and that connection then serves everything put on it. Browser-shaped
headers changed nothing. `FAHttpClient`'s `EventListener` tags each attempt with the
connection that carried it (`conn=`, `System.identityHashCode`, so per process) and
whether it opened it (`new=`). Over eight cold runs: a median 73% of requests on a new
connection drew 403, and **0** of ~600 on a reused one. So the retry loop is sampling
connections, and failures are front-loaded on a cold launch.

If you touch the instrument: `connectStart` fires on OkHttp 5's fast-fallback threads,
so bind the per-call state in `create(call)`, not via a `ThreadLocal` in the callback.

Getting more requests onto warm connections looked like the lever. Each way to pull it
was measured A-B-A on cold runs, and rejected:

- **A launch ramp** (one cold connection per host, widen on success): serialised the
  draws as intended, and opened *more* connections (21.5 vs 17.5 and 14.0) and lost
  more images. Six simultaneous draws need only one winner.
- **HTTP/2.** It coalesces `www.`, `t.` and `a.` onto one connection (2.5 distinct
  connections against h1's 21–32) and hit 0% 403 — and the repair could not repair it:
  0 of 26 post-repair retries came back 200, and three of eight runs lost 14–35 images
  where the h1 arms lost at most 5. An h2 challenge carries no `Connection: close`, so
  evicting and redialling draws the same verdict. h1's 20–60 connections are
  independent draws.

**The number of connections is not the thing to minimise; being able to redraw is.** The
protocol is pinned to h1 in `FAHttpClient.shared()`; re-measuring h2 means editing that
one `.protocols(…)` line. Run-to-run spread is bimodal (0% to 99% on one host in one
session), so judge a change A-B-A and on each arm's *worst* run, not its median.

## Measured outcomes

- **Before/after the pipeline work** (cold, disk cache wiped): first visible thumbnail
  4783 → 342 ms, requests per feed page 148 → 84, prefetches used 0 → 72 of 72. The
  visible rows had been queued behind ~144 unbounded prefetches.
- **Moving to Kingfisher** (2026-09-05, A-B-A): no run lost an image, against a worst of
  3–5 per shipping arm; first `t.` 200 at a median 542 ms. The transport was unchanged,
  so the claim is only that it costs nothing. Its review fixes (memory cap, decode
  coalescing) landed within drift.
