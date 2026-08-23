//
//  FACoilBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing the native-Swift image layer. FurAffinityUI is a *native*
//  Skip module (its Swift is compiled directly, not transpiled), so it cannot
//  `import coil3.*`/`okhttp3.*` the way SkipUI can. Instead this class is called from
//  Swift by class name through SkipBridge's AnyDynamicObject — see CoilImageLoader.swift.
//
//  It owns one OkHttpClient that replays FA's Cloudflare clearance — the byte-exact
//  WebView User-Agent plus the WebView Cookie header (cf_clearance + __cf_bm + auth) —
//  via an interceptor, the analog of the iOS Kingfisher DownloadDelegate. Credentials
//  are seeded once after login via `configure`; the interceptor reads the volatile
//  companion fields each request, so a CF re-solve just calls configure again.
//
//  Only coil3's standalone `DiskCache` is used, not its `ImageLoader`: an ImageRequest
//  decodes a full-resolution Bitmap that we then throw away, and the caller wants a
//  file, not pixels. So we download with OkHttp straight into the cache and hand Swift
//  back an on-disk **path** — no full-size image ever crosses JNI, and nothing is
//  decoded here.
//
//  Retry: FA's avatar host (a.furaffinity.net) issues probabilistic Cloudflare
//  challenges to any bare client (proven: URLSession and OkHttp both flip 200/403
//  run-to-run), so `fetchResult` retries a challenged download a few times with
//  backoff. HTTP/1.1 is pinned because HTTP/2 draws more challenges (spike finding).
//  It *reports* that retry story back to Swift as JSON rather than logging it:
//  android.util.Log never reaches the log file Settings exports, so anything worth
//  keeping has to be logged on the Swift side.
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against coil3/okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import android.util.Log
import coil3.disk.DiskCache
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okio.Path.Companion.toOkioPath
import org.json.JSONArray
import org.json.JSONObject
import skip.foundation.ProcessInfo

/// Instantiated once from Swift (`AnyDynamicObject(className:)`) and retained for the
/// app lifetime; all real state lives in the companion so the shared client, disk cache
/// and interceptor headers are single-sourced regardless of the caller.
class FACoilBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun configure(userAgent: String, cookie: String): Boolean = Companion.configure(userAgent, cookie)

    fun isCached(url: String): Boolean = Companion.isCached(url)

    fun cachedPath(url: String): String? = Companion.cachedPath(url)

    fun fetchResult(url: String): String = Companion.fetchResult(url)

    fun probeHeaders(urlsJson: String): String = Companion.probeHeaders(urlsJson)

    fun cacheSizeBytes(): Long = Companion.cacheSizeBytes()

    fun clearCache(): Boolean = Companion.clearCache()

    companion object {
        private const val TAG = "FACoilBridge"
        // FA challenges roughly half of all bare requests (measured: ~13% of URLs still
        // failed after 3 attempts, on both the Coil and the direct-OkHttp path). Each
        // attempt is independent, so a couple more take that tail from ~13% to ~3%, and
        // a retry now costs ~35 ms rather than a full Coil decode.
        private const val MAX_ATTEMPTS = 5
        private const val MAX_CONCURRENT_PER_HOST = 6

        @Volatile private var userAgent = ""
        @Volatile private var cookie = ""
        @Volatile private var sharedCache: DiskCache? = null
        @Volatile private var sharedClient: OkHttpClient? = null
        @Volatile private var probeClient: OkHttpClient? = null

        fun configure(userAgent: String, cookie: String): Boolean {
            this.userAgent = userAgent
            this.cookie = cookie
            return true
        }

        fun isCached(url: String): Boolean = cachedPath(url) != null

        /// On-disk path of `url`'s already-cached bytes, or null if it isn't cached.
        ///
        /// The snapshot (a read lock) is released before the path is handed back, so a
        /// concurrent eviction in that window would leave Swift with a stale path; it
        /// just decodes to nil and takes the existing failure path. With a 256 MB cache
        /// and ~100 KB thumbnails this is not worth holding a lock across JNI for.
        fun cachedPath(url: String): String? =
            diskCache().openSnapshot(url)?.use { it.data.toString() }

        /// Path of `url`'s bytes plus what it took to get them, as JSON:
        ///   {"path":"…","attempts":2,"bytes":98304,"ms":611,"failures":["HTTP 403"]}
        /// `path` is absent when every attempt failed. Swift does the logging —
        /// android.util.Log never reaches the exported application log.
        fun fetchResult(url: String): String {
            val start = System.nanoTime()
            val failures = JSONArray()
            val json = JSONObject().put("failures", failures)

            cachedPath(url)?.let {
                return json.put("path", it).put("attempts", 0).put("ms", ms(start)).toString()
            }

            val cache = diskCache()
            val request = Request.Builder().url(url).build()

            var attempt = 0
            while (true) {
                attempt++
                val failure = try {
                    sharedClient().newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            // Name Cloudflare's verdict: `cf-mitigated=challenge` is a
                            // bot-score challenge, its absence on a 403 a WAF/hotlink
                            // block. Kept as one string so the JSON contract and
                            // CoilImageLoader's failure line need no change.
                            val mitigated = response.header("cf-mitigated")
                                ?.let { " cf-mitigated=$it" } ?: ""
                            val ray = response.header("cf-ray")?.let { " ray=$it" } ?: ""
                            "HTTP ${response.code}$mitigated$ray"
                        } else {
                            val editor = cache.openEditor(url)
                            if (editor == null) {
                                // Another thread is writing the same key; it will win.
                                "editor busy"
                            } else {
                                try {
                                    val bytes = cache.fileSystem.write(editor.data) {
                                        writeAll(response.body!!.source())
                                    }
                                    val path = editor.commitAndOpenSnapshot()
                                        ?.use { it.data.toString() }
                                    if (path != null) {
                                        return json.put("path", path)
                                            .put("attempts", attempt)
                                            .put("bytes", bytes)
                                            .put("ms", ms(start))
                                            .toString()
                                    }
                                    "no snapshot after commit"
                                } catch (e: Exception) {
                                    editor.abort()
                                    throw e
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.toString()
                }

                failures.put(failure)
                if (attempt >= MAX_ATTEMPTS) {
                    return json.put("attempts", attempt).put("ms", ms(start)).toString()
                }
                Thread.sleep(250L * attempt)
            }
        }

        // MARK: Header A/B probe
        //
        // Whether a.furaffinity.net's 403s are a Cloudflare *challenge* or a plain
        // WAF/hotlink block decides the fix — and so does whether the image request's
        // thin header set (User-Agent + Cookie) is what draws them, next to the seven
        // browser-consistent headers FAHTTPDataSource sends for a page.
        //
        // Run-to-run CF drift makes four separate app *runs* uninterpretable, so the
        // four variants are compared inside one run: a 4x4 Latin square over four URLs,
        // sequential and spaced out, each variant meeting each URL exactly once.
        // Debug-only — nothing in a release build calls it (see CoilImageLoader).

        /// The subresource analogue of `FAHTTPDataSource.browserHeaders`: what a browser
        /// sends for an `<img>` on a furaffinity.net page rather than for a top-level
        /// navigation. Kept here next to the interceptor — this is the transport layer,
        /// and pushing six static strings across JNI buys nothing.
        private val imageBrowserHeaders = listOf(
            "Accept" to "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            "Accept-Language" to "en-US,en;q=0.9",
            "Referer" to "https://www.furaffinity.net/",
            "sec-fetch-dest" to "image",
            "sec-fetch-mode" to "no-cors",
            "sec-fetch-site" to "same-site",
        )

        /// `cookie` minus its `__cf_bm` pair. FAWebSession reads the Cookie header for
        /// **www**.furaffinity.net and pushes it here verbatim; if `__cf_bm` is scoped to
        /// that host, replaying a mismatched one to `a.`/`t.` is itself a bot signal.
        private fun withoutCfBm(cookie: String) = cookie
            .split(";")
            .filterNot { it.trim().startsWith("__cf_bm=") }
            .joinToString("; ") { it.trim() }

        /// Runs the square over the FA-host URLs in `urlsJson` and returns a JSON array
        /// of `{variant, url, code, cfMitigated, cfRay, ms}`. Blocking, ~6 s for four
        /// URLs; Swift logs the rows, as with `fetchResult`.
        fun probeHeaders(urlsJson: String): String {
            val array = JSONArray(urlsJson)
            val urls = (0 until array.length())
                .mapNotNull { array.getString(it).toHttpUrlOrNull() }
                // Same gate as the interceptor: a Referer and the viewer's FA cookies
                // must never reach an attacker-authored third-party <img src>.
                .filter { it.isHttps && isFAHost(it.host) }
                .map { it.toString() }
            val rows = JSONArray()
            if (urls.isEmpty()) return rows.toString()

            val variants = listOf("S", "A", "B", "C", "D")
            // Round r pairs url j with variant (r + j) % 5: over five rounds every
            // variant meets every URL exactly once, and no two consecutive requests
            // repeat a variant — firing the same one twice in a row at the same host is
            // what inflated the second request's challenge rate in the earlier spike.
            for (round in variants.indices) {
                for ((j, url) in urls.withIndex()) {
                    rows.put(probeOnce(variants[(round + j) % variants.size], url))
                    Thread.sleep(300L)
                }
            }
            return rows.toString()
        }

        /// One probe request. Variants: **S** the production request itself, through the
        /// shared client and its interceptor; A the same headers but on the probe's own
        /// client; B adds the image browser headers; C strips `__cf_bm`; D does both.
        ///
        /// S is the control. Without it "every variant 403'd" cannot be read — it could
        /// mean the headers make no difference, or that the whole window was being
        /// challenged and the probe measured nothing.
        private fun probeOnce(variant: String, url: String): JSONObject {
            val row = JSONObject().put("variant", variant).put("url", url)
            val start = System.nanoTime()
            val builder = Request.Builder().url(url)
            if (variant != "S") {
                if (userAgent.isNotEmpty()) builder.header("User-Agent", userAgent)
                val jar = if (variant == "C" || variant == "D") withoutCfBm(cookie) else cookie
                if (jar.isNotEmpty()) builder.header("Cookie", jar)
                if (variant == "B" || variant == "D") {
                    for ((name, value) in imageBrowserHeaders) builder.header(name, value)
                }
            }
            val client = if (variant == "S") sharedClient() else probeClient()
            try {
                // The body is never read: this measures the verdict, not the bytes, and
                // must not populate the disk cache the real path is being judged on.
                client.newCall(builder.build()).execute().use { response ->
                    row.put("code", response.code)
                        .put("cfMitigated", response.header("cf-mitigated") ?: "")
                        .put("cfRay", response.header("cf-ray") ?: "")
                        // `Connection: close` on a 403 is what makes the verdict stick:
                        // the pooled connection dies with it, so the retry opens a fresh
                        // one and draws a fresh verdict.
                        .put("connection", response.header("Connection") ?: "")
                }
            } catch (e: Exception) {
                row.put("code", -1).put("error", e.toString())
            }
            return row.put("ms", ms(start))
        }

        /// The probe's own client. `sharedClient`'s interceptor forces `User-Agent` and
        /// `Cookie` onto every FA request, which would overwrite the very headers being
        /// compared — so this one carries no interceptor and each variant is explicit.
        private fun probeClient(): OkHttpClient {
            probeClient?.let { return it }
            synchronized(FACoilBridge::class.java) {
                probeClient?.let { return it }
                val client = OkHttpClient.Builder()
                    .protocols(listOf(Protocol.HTTP_1_1))
                    .build()
                probeClient = client
                return client
            }
        }

        /// Bytes currently held on disk. Backs the Settings row, so it is only ever
        /// read for display.
        fun cacheSizeBytes(): Long = diskCache().size

        /// Empties the disk cache. Coil's `clear()` deletes the whole cache directory
        /// and recreates it, so the same DiskCache instance stays usable.
        fun clearCache(): Boolean {
            return try {
                diskCache().clear()
                true
            } catch (e: Exception) {
                Log.e(TAG, "clearCache failed: $e")
                false
            }
        }

        private fun ms(startNanos: Long) = (System.nanoTime() - startNanos) / 1_000_000

        private fun context() = ProcessInfo.processInfo.androidContext

        private fun diskCache(): DiskCache {
            sharedCache?.let { return it }
            synchronized(FACoilBridge::class.java) {
                sharedCache?.let { return it }
                val cache = DiskCache.Builder()
                    .directory(context().cacheDir.resolve("fa_coil_cache").toOkioPath())
                    .maxSizeBytes(256L * 1024 * 1024)
                    .build()
                sharedCache = cache
                return cache
            }
        }

        // Mirrors FAURLs.isFAHost. `HttpUrl` has already lowercased the host.
        private fun isFAHost(host: String) =
            host == "furaffinity.net" || host.endsWith(".furaffinity.net")

        private fun sharedClient(): OkHttpClient {
            sharedClient?.let { return it }
            synchronized(FACoilBridge::class.java) {
                sharedClient?.let { return it }
                val client = OkHttpClient.Builder()
                    // HTTP/2 draws more Cloudflare challenges than HTTP/1.1 (spike +
                    // Phase A), so pin h1 to match the URLSession path that clears CF.
                    .protocols(listOf(Protocol.HTTP_1_1))
                    // The interceptor reads the volatile companion fields each request,
                    // so header refreshes (CF re-solve / re-login) need no rebuild.
                    .addInterceptor { chain ->
                        val request = chain.request()
                        // Image URLs reaching this loader are attacker-authored:
                        // FAHTMLNormalizer takes <img src> verbatim out of a user's
                        // description. An `endsWith` gate also matches
                        // evilfuraffinity.net, so one such <img> would hand that host
                        // the viewer's FA auth cookies and Cloudflare clearance.
                        // Third-party images still load — just unauthenticated.
                        if (request.isHttps && isFAHost(request.url.host)) {
                            val builder = request.newBuilder()
                            if (userAgent.isNotEmpty()) builder.header("User-Agent", userAgent)
                            if (cookie.isNotEmpty()) builder.header("Cookie", cookie)
                            chain.proceed(builder.build())
                        } else {
                            chain.proceed(request)
                        }
                    }
                    .build()
                // Governs *enqueued* calls only; `fetch` calls `execute()` synchronously,
                // so the real bound is FAImageStore's gate on the Swift side. Set to
                // match it (and URLSession's per-host default) in case we ever go async.
                client.dispatcher.maxRequestsPerHost = MAX_CONCURRENT_PER_HOST
                sharedClient = client
                return client
            }
        }
    }
}
