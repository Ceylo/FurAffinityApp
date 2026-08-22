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
- FA challenges roughly half of all bare image requests (probabilistic, per request), so
  the bridge's retry loop is load-bearing, not defensive padding.

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
