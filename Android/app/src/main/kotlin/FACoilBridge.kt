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
//  WebView User-Agent plus the WebView Cookie header — via an interceptor, the analog
//  of the iOS Kingfisher DownloadDelegate. Credentials are seeded after login via
//  `configure`; the interceptor reads the volatile companion fields each request, so a
//  CF re-solve just calls configure again.
//
//  Only coil3's standalone `DiskCache` is used, not its `ImageLoader`: the caller wants
//  a file, not pixels. So we download with OkHttp straight into the cache and hand Swift
//  back an on-disk **path** — nothing full-size crosses JNI, and nothing is decoded here.
//
//  Cloudflare judges the *connection*, not the request, which is what the retry loop
//  and the pinned HTTP/1.1 are for; `Android/docs/images.md` has the measurements and
//  the two rejected alternatives. Retry outcomes are *reported* to Swift as JSON rather
//  than logged: android.util.Log never reaches the log file Settings exports.
//
//  Cache policy is split between coil and us, because coil offers exactly one half of
//  it: `DiskCache.Builder` *requires* a maximum size (it defaults to 2% of the volume)
//  and has no expiry at all. So the ceiling below is coil's requirement, raised to 1 GB,
//  and the per-entry lifetime is ours, applied lazily in `cachedPath`. Together they
//  match iOS, where Kingfisher's `sizeLimit` is left at its unbounded default and the
//  expiry is 7-14 days from write. `FAImageStore.pruneStagedMedia` already covers the
//  `fa-media` staging directory at 7 days.
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against coil3/okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import android.util.Log
import coil3.disk.DiskCache
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import okhttp3.Call
import okhttp3.Connection
import okhttp3.EventListener
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
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun configure(userAgent: String, cookie: String): Boolean = Companion.configure(userAgent, cookie)

    fun isCached(url: String): Boolean = Companion.isCached(url)

    fun cachedPath(url: String): String? = Companion.cachedPath(url)

    fun fetchResult(url: String): String = Companion.fetchResult(url)

    fun cacheSizeBytes(): Long = Companion.cacheSizeBytes()

    fun clearCache(): Boolean = Companion.clearCache()

    companion object {
        private const val TAG = "FACoilBridge"
        // Each attempt is an independent draw: the challenge closes the connection, so
        // the next one necessarily opens a fresh one. A cold launch can exhaust all
        // five on a host that never warms a connection, and each retry costs the
        // challenge round-trip rather than a warm fetch — see Android/docs/images.md.
        private const val MAX_ATTEMPTS = 5
        private const val MAX_CONCURRENT_PER_HOST = 6

        /// The loop has no iOS counterpart — Kingfisher exposes `.retryStrategy` and
        /// `Kingfisher+FA.swift` never sets it — because iOS doesn't need one: URLSession
        /// negotiates h2 and keeps one connection per host, while this client is pinned
        /// to h1 and draws a fresh connection, and so a fresh verdict, per request.
        ///
        /// A flat second, matching `www.furaffinity.net`'s `Crawl-delay: 1`. That
        /// directive doesn't bind here (`d.`/`t.`/`a.` serve no `robots.txt`, and
        /// `ProgressiveLoadItem.crawlingDelay` is where the app really crawls), but
        /// nothing should hit an FA host faster than it either.
        private const val RETRY_BACKOFF_MS = 1000L

        /// Whether a failed response could plausibly come back different on a fresh
        /// connection. A 4xx is the origin's own answer, so re-asking it just burns
        /// attempts and one of `FAImageStore`'s permits — FA answers a missing avatar
        /// with a **404**, which `FAImage` substitutes for anyway. The exceptions mean
        /// "ask again": 403 is Cloudflare's per-connection verdict and the reason this
        /// loop exists, 408 and 429 say so by definition.
        private fun worthRedrawing(code: Int) =
            code !in 400..499 || code == 403 || code == 408 || code == 429

        // MARK: Connection instrument
        //
        // Which connection carried an attempt, and whether that attempt opened it —
        // the causal variable behind every 403 (Android/docs/images.md).
        //
        // `fetchResult` calls `execute()` synchronously, so a ThreadLocal holds the
        // per-attempt state with no map and no locking. The factory matters: OkHttp 5
        // opens connections on its own fast-fallback threads, so a listener resolving
        // the ThreadLocal inside a callback picks up an unrelated Draw. `create` runs
        // in `RealCall.<init>`, on the calling thread, so the per-call listener
        // captures the right one. Reset per *attempt* — each is its own draw.

        private class Draw {
            @Volatile var id: Int? = null
            @Volatile var isNew = false

            fun reset() {
                id = null
                isNew = false
            }

            /// Appended to each failure string, so the JSON keeps its shape instead of
            /// growing a per-attempt array.
            fun suffix() = id?.let { " conn=$it new=$isNew" } ?: ""
        }

        private val draw = ThreadLocal.withInitial { Draw() }

        private val connectionTracer = object : EventListener.Factory {
            override fun create(call: Call): EventListener {
                val attempt = draw.get()
                return object : EventListener() {
                    /// Fires only when no pooled connection was available: this request
                    /// is paying for a handshake, and drawing a fresh CF verdict.
                    override fun connectStart(
                        call: Call,
                        inetSocketAddress: InetSocketAddress,
                        proxy: Proxy,
                    ) {
                        attempt.isNew = true
                    }

                    override fun connectionAcquired(call: Call, connection: Connection) {
                        attempt.id = System.identityHashCode(connection)
                    }
                }
            }
        }

        @Volatile private var userAgent = ""
        @Volatile private var cookie = ""
        @Volatile private var sharedCache: DiskCache? = null
        @Volatile private var sharedClient: OkHttpClient? = null

        fun configure(userAgent: String, cookie: String): Boolean {
            this.userAgent = userAgent
            this.cookie = cookie
            return true
        }

        fun isCached(url: String): Boolean = cachedPath(url) != null

        /// Spread across the window rather than random, so a deadline survives a
        /// restart while a cache filled in one session still doesn't expire at once.
        /// Kotlin's `String.hashCode` is specified, unlike Swift's per-process-seeded
        /// one; widened to `Long` because `Int.MIN_VALUE.abs()` is `Int.MIN_VALUE`.
        private fun lifetimeMillis(url: String): Long {
            val spreadDays = Math.abs(url.hashCode().toLong()) % 8
            return (7 + spreadDays) * 24 * 60 * 60 * 1000
        }

        /// On-disk path of `url`'s already-cached bytes, or null if it isn't cached or
        /// has expired — `fetchResult` and `isCached` both come through here, which is
        /// what makes one expiry check enough.
        ///
        /// The snapshot (a read lock) is released before the path is handed back, so a
        /// concurrent eviction in that window would leave Swift with a stale path; it
        /// just decodes to nil and takes the existing failure path. With a 1 GB cache
        /// and ~100 KB thumbnails this is not worth holding a lock across JNI for.
        fun cachedPath(url: String): String? {
            val path = diskCache().openSnapshot(url)?.use { it.data.toString() } ?: return null
            val age = System.currentTimeMillis() - File(path).lastModified()
            if (age > lifetimeMillis(url)) {
                diskCache().remove(url)
                return null
            }
            return path
        }

        /// Path of `url`'s bytes plus what it took to get them, as JSON:
        ///   {"path":"…","attempts":2,"bytes":98304,"conn":1234,"newConn":true,
        ///    "ms":611,"failures":["HTTP 403 … conn=5678 new=true"]}
        /// `conn`/`newConn` describe the winning attempt; every failed attempt carries
        /// its own draw in its string. `path` is absent when every attempt failed.
        /// Swift does the logging — android.util.Log never reaches the exported log.
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
            var proto = ""
            val conn = draw.get()
            // Not every failure is worth a fresh draw; see `worthRedrawing`. Anything
            // that is not an HTTP status — a socket error, a cache-editor race — keeps
            // the retry it always had.
            var redraw = true
            while (true) {
                attempt++
                conn.reset()
                redraw = true
                val failure = try {
                    sharedClient().newCall(request).execute().use { response ->
                        proto = response.protocol.toString()
                        if (!response.isSuccessful) {
                            // Name Cloudflare's verdict: `cf-mitigated=challenge` is a
                            // bot-score challenge, its absence on a 403 a WAF/hotlink
                            // block. Kept as one string so the JSON contract and
                            // CoilImageLoader's failure line need no change.
                            val mitigated = response.header("cf-mitigated")
                                ?.let { " cf-mitigated=$it" } ?: ""
                            val ray = response.header("cf-ray")?.let { " ray=$it" } ?: ""
                            redraw = worthRedrawing(response.code)
                            "HTTP ${response.code}$mitigated$ray${conn.suffix()}"
                        } else {
                            val editor = cache.openEditor(url)
                            if (editor == null) {
                                // Another thread is writing the same key; it will win.
                                "editor busy${conn.suffix()}"
                            } else {
                                try {
                                    val bytes = cache.fileSystem.write(editor.data) {
                                        writeAll(response.body!!.source())
                                    }
                                    val path = editor.commitAndOpenSnapshot()
                                        ?.use { it.data.toString() }
                                    if (path != null) {
                                        conn.id?.let { json.put("conn", it) }
                                        return json.put("path", path)
                                            .put("attempts", attempt)
                                            .put("bytes", bytes)
                                            .put("proto", proto)
                                            .put("newConn", conn.isNew)
                                            .put("ms", ms(start))
                                            .toString()
                                    }
                                    "no snapshot after commit${conn.suffix()}"
                                } catch (e: Exception) {
                                    editor.abort()
                                    throw e
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    "$e${conn.suffix()}"
                }

                failures.put(failure)
                if (attempt >= MAX_ATTEMPTS || !redraw) {
                    return json.put("attempts", attempt)
                        .put("proto", proto)
                        .put("ms", ms(start))
                        .toString()
                }
                Thread.sleep(RETRY_BACKOFF_MS)
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
                    .maxSizeBytes(1L * 1024 * 1024 * 1024)
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
                    // h1 is pinned, and h2 was measured rather than assumed. Since
                    // Cloudflare judges the connection, h2 looked like the fix — FA's
                    // CDN offers it, and it multiplexes a whole burst onto one
                    // connection instead of h1's one per concurrent request. It is
                    // also what iOS gets for free (URLSession always negotiates h2 and
                    // cannot be told not to). Ten cold-launch runs on one emulator
                    // session, five each, say it is a wash:
                    //
                    //     h2  444 responses, 12% 403, 7 images lost, 3/5 clean runs
                    //     h1  463 responses, 15% 403, 6 images lost, 1/5 clean runs
                    //
                    // h2 has the better median and the worse tail: its one connection
                    // is a single point of failure, so a bad draw loses every avatar
                    // at once (one run lost 7 of 8) where h1's six draws decorrelate
                    // and its retries recover. No reliable win, so keep h1.
                    .protocols(listOf(Protocol.HTTP_1_1))
                    .eventListenerFactory(connectionTracer)
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
