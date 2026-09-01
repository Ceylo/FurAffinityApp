//
//  FAHttpBridge.kt
//  FurAffinity (Android)
//
//  Kotlin side of the page transport: one HTTP exchange over the shared
//  `FAHttpClient`, so page fetches and image fetches ride the same connection pool.
//  Called from native Swift by class name through SkipBridge's AnyDynamicObject —
//  see OkHttpTransport.swift.
//
//  The request arrives as JSON that Swift built, and it is used verbatim: the URL,
//  the header set, the percent-encoded body and the per-hop credentials are all
//  computed in `FAHTTPDataSource`, where they are tested. Nothing here derives a
//  cookie or re-encodes a body.
//
//  **The response body travels as a file path, not an inline string.** The contract
//  above this is `Data`, and `FASubmissionsPage` throws on invalid UTF-8 — where
//  Kotlin's `response.body.string()` substitutes U+FFFD silently and turns a
//  truncated page into a confusing parser failure instead of a clean throw at the
//  transport boundary. It is also the house rule (no bytes cross JNI) and cheaper
//  than escaping ~135 KB into a JVM UTF-16 string and back.
//

package fur.affinity.ui

import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import skip.foundation.ProcessInfo

class FAHttpBridge {
    fun perform(requestJson: String): String = Companion.perform(requestJson)

    fun repair(observedEpoch: Long): String = FAHttpClient.evictIfUnchanged(observedEpoch)

    fun epoch(): Long = FAHttpClient.connectionEpoch()

    fun poolStats(): String = FAHttpClient.poolStats()

    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun setHTTP2Enabled(enabled: Boolean): Boolean = FAHttpClient.setHTTP2Enabled(enabled)

    fun isHTTP2Enabled(): Boolean = FAHttpClient.isHTTP2Enabled()

    companion object {
        /// Response headers worth carrying back. An allowlist, and **never**
        /// `set-cookie`: nothing above consumes it, and logging it would put a live
        /// Cloudflare clearance in the log file Settings exports.
        private val CARRIED = setOf(
            "cf-mitigated", "cf-ray", "cf-cache-status", "connection",
            "content-type", "content-length", "location", "server",
        )

        /// Bodies Swift never got to read — it crashed, or was killed between the
        /// write and its `defer`-ed unlink. Swept on construction and periodically,
        /// so the directory is bounded by a minute's traffic rather than by uptime.
        private const val BODY_TTL_MS = 60_000L
        private const val SWEEP_EVERY = 32
        private val calls = AtomicInteger(0)

        init {
            sweep()
        }

        private fun bodyDir(): File {
            // `FileManager.temporaryDirectory` is this same directory on Android, so
            // Swift opens the path directly with no translation.
            val dir = File(ProcessInfo.processInfo.androidContext.cacheDir, "fa_http")
            dir.mkdirs()
            return dir
        }

        private fun sweep() {
            val cutoff = System.currentTimeMillis() - BODY_TTL_MS
            bodyDir().listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
        }

        /// One exchange. Redirects are OkHttp's (the network interceptor re-scopes the
        /// credentials per hop); retries, challenge handling and the cookie merge are
        /// all above this, in Swift.
        fun perform(requestJson: String): String {
            if (calls.incrementAndGet() % SWEEP_EVERY == 0) sweep()

            val spec = JSONObject(requestJson)
            val builder = Request.Builder().url(spec.getString("url"))

            val headers = spec.optJSONObject("headers")
            var contentType: String? = null
            headers?.keys()?.forEach { name ->
                val value = headers.getString(name)
                if (name.equals("Content-Type", ignoreCase = true)) contentType = value
                builder.header(name, value)
            }

            // Always tagged, even with empty strings: without a tag the interceptor
            // falls back to the pushed image credentials, and a page request must
            // never inherit a pair Swift did not compute for it.
            val creds = spec.optJSONObject("credentials")
            builder.tag(
                FACredentials::class.java,
                FACredentials(
                    creds?.optString("userAgent", "") ?: "",
                    creds?.optString("cookie", "") ?: "",
                )
            )

            if (spec.optString("method", "GET") == "POST") {
                // The body and its Content-Type both come from Swift, and only
                // together: `FAHTTPDataSource` sets neither when a POST has no
                // parameters, and URLSession then sends no body and no
                // Content-Type. Deriving one here would diverge from that.
                val body = if (spec.has("body")) spec.getString("body") else null
                builder.post((body ?: "").toRequestBody(contentType?.toMediaType()))
            }

            val draw = FAHttpClient.draw.get()
            draw.reset()
            val start = System.nanoTime()

            return try {
                FAHttpClient.shared().newCall(builder.build()).execute().use { response ->
                    val carried = JSONObject()
                    for (name in response.headers.names()) {
                        val lower = name.lowercase()
                        if (lower in CARRIED) carried.put(lower, response.header(name) ?: "")
                    }

                    val file = File(bodyDir(), "${UUID.randomUUID()}.body")
                    val bytes = response.body?.byteStream()?.use { input ->
                        file.outputStream().use { output -> input.copyTo(output) }
                    } ?: 0L

                    val json = JSONObject()
                        .put("status", response.code)
                        .put("proto", response.protocol.toString())
                        .put("newConn", draw.isNew)
                        .put("epoch", FAHttpClient.connectionEpoch())
                        .put("finalUrl", response.request.url.toString())
                        .put("bytes", bytes)
                        .put("ms", (System.nanoTime() - start) / 1_000_000)
                        .put("bodyPath", file.absolutePath)
                        .put("headers", carried)
                    draw.id?.let { json.put("conn", it) }
                    json.toString()
                }
            } catch (e: Exception) {
                JSONObject().put("error", e.toString())
                    .put("ms", (System.nanoTime() - start) / 1_000_000)
                    .put("epoch", FAHttpClient.connectionEpoch())
                    .toString()
            }
        }
    }
}
