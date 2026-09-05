//
//  FAImageFetchBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing the native-Swift image layer. FurAffinityUI is a *native*
//  Skip module (its Swift is compiled directly, not transpiled), so it cannot
//  `import okhttp3.*` the way SkipUI can. Instead this class is called from
//  Swift by class name through SkipBridge's AnyDynamicObject — see ImageFetchBridge.swift.
//
//  The HTTP client, its connection pool, the credential interceptor and the
//  connection instrument all live in `FAHttpClient`, shared with the page path — one
//  pool is the whole point. What stays here is what is image-specific: the retry loop.
//
//  Nothing is cached and nothing is decoded here any more: Kingfisher owns both caches
//  on this platform, so a fetch lands in a throwaway file under `cacheDir` and Swift is
//  handed its **path**. Nothing full-size crosses JNI, and the caller unlinks the file
//  the moment it has read it (`ImageFetchBridge.fetchImageData`).
//
//  Cloudflare judges the *connection*, not the request, which is what the retry loop
//  is for; `Android/docs/images.md` has the measurements and the two rejected
//  alternatives. Retry outcomes are *reported* to Swift as JSON rather than logged:
//  android.util.Log never reaches the log file Settings exports.
//
//  Lives in the app Gradle module (not the FurAffinityUI module) so it compiles
//  against okhttp declared in Android/app/build.gradle.kts; reflection loads it
//  by name at runtime from the single APK classloader.
//

package fur.affinity.ui

import java.io.File
import okhttp3.Request
import okio.buffer
import okio.sink
import org.json.JSONArray
import org.json.JSONObject
import skip.foundation.ProcessInfo

/// Instantiated once from Swift (`AnyDynamicObject(className:)`) and retained for the
/// app lifetime; all real state lives in the companion so the shared client and the
/// interceptor headers are single-sourced regardless of the caller.
class FAImageFetchBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun configure(userAgent: String, cookie: String): Boolean =
        FAHttpClient.configure(userAgent, cookie)

    fun fetchResult(url: String): String = Companion.fetchResult(url)

    companion object {
        // Each attempt is an independent draw: the challenge closes the connection, so
        // the next one necessarily opens a fresh one. A cold launch can exhaust all
        // five on a host that never warms a connection, and each retry costs the
        // challenge round-trip rather than a warm fetch — see Android/docs/images.md.
        private const val MAX_ATTEMPTS = 5

        /// Flat rather than a ramp, and a second because that is what `robots.txt` asks
        /// of a crawler — measured A-B-A in `Android/docs/images.md`, which also covers
        /// why this loop has no iOS counterpart.
        private const val RETRY_BACKOFF_MS = 1000L

        /// Whether a failed response could plausibly come back different on a fresh
        /// connection. A 4xx is the origin's own answer, so re-asking it just burns
        /// attempts and one of `FAImageStore`'s permits — FA answers a missing avatar
        /// with a **404**, which `FAImage` substitutes for anyway. The exceptions mean
        /// "ask again": 403 is Cloudflare's per-connection verdict and the reason this
        /// loop exists, 408 and 429 say so by definition.
        private fun worthRedrawing(code: Int) =
            code !in 400..499 || code == 403 || code == 408 || code == 429

        /// Where a fetch's bytes land on their way to Swift. Not a cache: each file is
        /// read once and unlinked, and a sweep on first use clears anything a crash
        /// left behind.
        private const val STAGING_DIR = "fa-image-fetch"
        private const val STALE_STAGING_MS = 60 * 60 * 1000L
        @Volatile private var sweptStaging = false

        private fun stagingDir(): File {
            val dir = File(context().cacheDir, STAGING_DIR)
            dir.mkdirs()
            if (!sweptStaging) {
                synchronized(FAImageFetchBridge::class.java) {
                    if (!sweptStaging) {
                        sweptStaging = true
                        val cutoff = System.currentTimeMillis() - STALE_STAGING_MS
                        dir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
                    }
                }
            }
            return dir
        }

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
                            // ImageFetchBridge's failure line need no change.
                            val mitigated = response.header("cf-mitigated")
                                ?.let { " cf-mitigated=$it" } ?: ""
                            val ray = response.header("cf-ray")?.let { " ray=$it" } ?: ""
                            redraw = worthRedrawing(response.code)
                            challenged = response.code == 403 &&
                                response.header("cf-mitigated") == "challenge"
                            "HTTP ${response.code}$mitigated$ray${conn.suffix()}"
                        } else {
                            val file = File.createTempFile("img", null, stagingDir())
                            try {
                                val bytes = file.sink().buffer().use {
                                    it.writeAll(response.body!!.source())
                                }
                                conn.id?.let { json.put("conn", it) }
                                return json.put("path", file.path)
                                    .put("attempts", attempt)
                                    .put("bytes", bytes)
                                    .put("proto", proto)
                                    .put("newConn", conn.isNew)
                                    .put("ms", ms(start))
                                    .put("epoch", FAHttpClient.connectionEpoch())
                                    .toString()
                            } catch (e: Exception) {
                                file.delete()
                                throw e
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
                Thread.sleep(RETRY_BACKOFF_MS)
            }
        }

        private fun ms(startNanos: Long) = (System.nanoTime() - startNanos) / 1_000_000

        private fun context() = ProcessInfo.processInfo.androidContext
    }
}
