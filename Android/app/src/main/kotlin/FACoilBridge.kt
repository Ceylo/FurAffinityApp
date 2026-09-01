//
//  FACoilBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing the native-Swift image layer. FurAffinityUI is a *native*
//  Skip module (its Swift is compiled directly, not transpiled), so it cannot
//  `import coil3.*`/`okhttp3.*` the way SkipUI can. Instead this class is called from
//  Swift by class name through SkipBridge's AnyDynamicObject — see CoilImageLoader.swift.
//
//  The HTTP client, its connection pool, the credential interceptor and the
//  connection instrument all live in `FAHttpClient`, shared with the page path — one
//  pool is the whole point. What stays here is what is image-specific: the coil disk
//  cache and the retry loop.
//
//  Only coil3's standalone `DiskCache` is used, not its `ImageLoader`: the caller wants
//  a file, not pixels. So we download with OkHttp straight into the cache and hand Swift
//  back an on-disk **path** — nothing full-size crosses JNI, and nothing is decoded here.
//
//  Cloudflare judges the *connection*, not the request, which is what the retry loop
//  is for; `Android/docs/images.md` has the measurements and the two rejected
//  alternatives. Retry outcomes are *reported* to Swift as JSON rather than logged:
//  android.util.Log never reaches the log file Settings exports.
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against coil3/okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import android.util.Log
import coil3.disk.DiskCache
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
    fun configure(userAgent: String, cookie: String): Boolean =
        FAHttpClient.configure(userAgent, cookie)

    fun isCached(url: String): Boolean = Companion.isCached(url)

    fun cachedPath(url: String): String? = Companion.cachedPath(url)

    fun fetchResult(url: String): String = Companion.fetchResult(url)

    fun connectionEpoch(): Long = FAHttpClient.connectionEpoch()

    fun evictIfUnchanged(observedEpoch: Long): String = FAHttpClient.evictIfUnchanged(observedEpoch)

    fun cacheSizeBytes(): Long = Companion.cacheSizeBytes()

    fun clearCache(): Boolean = Companion.clearCache()

    companion object {
        private const val TAG = "FACoilBridge"
        // Each attempt is an independent draw: the challenge closes the connection, so
        // the next one necessarily opens a fresh one. A cold launch can exhaust all
        // five on a host that never warms a connection, and each retry costs the
        // challenge round-trip rather than a warm fetch — see Android/docs/images.md.
        private const val MAX_ATTEMPTS = 5
        /// Whether a failed response could plausibly come back different on a fresh
        /// connection. A 4xx is the origin's own answer, so re-asking it just burns
        /// attempts and one of `FAImageStore`'s permits — FA answers a missing avatar
        /// with a **404**, which `FAImage` substitutes for anyway. The exceptions mean
        /// "ask again": 403 is Cloudflare's per-connection verdict and the reason this
        /// loop exists, 408 and 429 say so by definition.
        private fun worthRedrawing(code: Int) =
            code !in 400..499 || code == 403 || code == 408 || code == 429

        @Volatile private var sharedCache: DiskCache? = null

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
        ///   {"path":"…","attempts":2,"bytes":98304,"conn":1234,"newConn":true,
        ///    "ms":611,"epoch":3,"failures":["HTTP 403 … conn=5678 new=true"]}
        /// `conn`/`newConn` describe the winning attempt; every failed attempt carries
        /// its own draw in its string. `path` is absent when every attempt failed.
        /// Swift does the logging — android.util.Log never reaches the exported log.
        ///
        /// `"challenged":true` means Cloudflare's verdict, not a dead URL: Swift can
        /// repair that — park on the solve the page path is already asking for, evict,
        /// and redial — where retrying here just burns the same connection's verdict
        /// five times. Reported instead of retried under h2 immediately (the retry
        /// rides the same connection) and under h1 only once the attempts are spent,
        /// so h1 keeps the redraws `Connection: close` makes genuine.
        fun fetchResult(url: String): String {
            val start = System.nanoTime()
            val failures = JSONArray()
            val json = JSONObject().put("failures", failures)

            cachedPath(url)?.let {
                return json.put("path", it).put("attempts", 0).put("ms", ms(start))
                    .put("epoch", FAHttpClient.connectionEpoch()).toString()
            }

            val cache = diskCache()
            val request = Request.Builder().url(url).build()

            var attempt = 0
            var proto = ""
            val conn = FAHttpClient.draw.get()
            // Not every failure is worth a fresh draw; see `worthRedrawing`. Anything
            // that is not an HTTP status — a socket error, a cache-editor race — keeps
            // the retry it always had.
            var redraw = true
            var challenged = false
            while (true) {
                attempt++
                conn.reset()
                redraw = true
                challenged = false
                val failure = try {
                    FAHttpClient.shared().newCall(request).execute().use { response ->
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
                            challenged = response.code == 403 &&
                                response.header("cf-mitigated") == "challenge"
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
                                            .put("epoch", FAHttpClient.connectionEpoch())
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
                // Hand a challenge back to Swift rather than redrawing into it. Under
                // h1 that only happens once the attempts are spent — each of those is
                // a genuinely new connection, since the challenge closes the last one.
                // Under anything else the retry rides the same connection, so the
                // first challenge is already the whole answer.
                if (challenged && (proto != "http/1.1" || attempt >= MAX_ATTEMPTS)) {
                    conn.id?.let { json.put("conn", it) }
                    return json.put("challenged", true)
                        .put("attempts", attempt)
                        .put("proto", proto)
                        .put("newConn", conn.isNew)
                        .put("ms", ms(start))
                        .put("epoch", FAHttpClient.connectionEpoch())
                        .toString()
                }
                if (attempt >= MAX_ATTEMPTS || !redraw) {
                    return json.put("attempts", attempt)
                        .put("proto", proto)
                        .put("ms", ms(start))
                        .put("epoch", FAHttpClient.connectionEpoch())
                        .toString()
                }
                // Inside the permit on purpose: this sleep *is* the pacing, and
                // freeing the permit across it is what let ~80 URLs resume in
                // lockstep and 403 (Android/docs/images.md).
                Thread.sleep(250L * attempt)
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

    }
}
